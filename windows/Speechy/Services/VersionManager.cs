using System.Net.Http;
using System.Text.Json;

namespace Speechy.Services;

/// <summary>
/// Checks the version API and triggers force-update if current version is below minimum.
/// Mirrors macOS VersionManager.
/// </summary>
public class VersionManager
{
    private static readonly Lazy<VersionManager> _instance = new(() => new VersionManager());
    public static VersionManager Instance => _instance.Value;

    private const string BaseUrl = "https://speechy.frkn.com.tr";

    /// <summary>
    /// Returns the current application version as a "Major.Minor.Build" string,
    /// falling back to "1.0.0" if the assembly version is unavailable.
    /// </summary>
    public string CurrentVersion
    {
        get
        {
            var asm = System.Reflection.Assembly.GetExecutingAssembly();
            var ver = asm.GetName().Version;
            return ver != null ? $"{ver.Major}.{ver.Minor}.{ver.Build}" : "1.0.0";
        }
    }

    /// <summary>
    /// Returns true if version a is strictly less than version b (semver X.Y.Z).
    /// </summary>
    public bool IsVersionLessThan(string a, string b)
    {
        var aParts = a.Split('.').Select(x => int.TryParse(x, out var n) ? n : 0).ToArray();
        var bParts = b.Split('.').Select(x => int.TryParse(x, out var n) ? n : 0).ToArray();
        int count = Math.Max(aParts.Length, bParts.Length);
        for (int i = 0; i < count; i++)
        {
            int av = i < aParts.Length ? aParts[i] : 0;
            int bv = i < bParts.Length ? bParts[i] : 0;
            if (av < bv) return true;
            if (av > bv) return false;
        }
        return false;
    }

    /// <summary>
    /// Checks version endpoint asynchronously. If current version is below minimum,
    /// calls onUpdateRequired on the UI thread.
    /// Silently ignores network errors.
    /// </summary>
    public async Task CheckVersionAsync(Action<string, string, string> onUpdateRequired)
    {
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
            var url = $"{BaseUrl}/api/version/check?platform=windows";
            var response = await client.GetStringAsync(url);
            var json = JsonDocument.Parse(response).RootElement;

            var minimumVersion = json.GetProperty("minimum_version").GetString() ?? "1.0.0";
            var latestVersion  = json.GetProperty("latest_version").GetString()  ?? "1.0.0";
            var updateUrl      = json.TryGetProperty("update_url", out var u) ? u.GetString() ?? BaseUrl : BaseUrl;

            Log.Info($"Version check: current={CurrentVersion} latest={latestVersion} minimum={minimumVersion}");

            if (IsVersionLessThan(CurrentVersion, minimumVersion))
            {
                Log.Info("Version check: BELOW MINIMUM — forcing update");
                onUpdateRequired(minimumVersion, latestVersion, updateUrl);
            }
            else
            {
                Log.Info("Version check: OK");
            }
        }
        catch (Exception ex)
        {
            Log.Info($"Version check: skipped ({ex.Message})");
        }
    }
}
