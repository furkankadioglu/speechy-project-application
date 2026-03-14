using System.ComponentModel;
using System.Net.Http;
using System.Net.Http.Json;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Speechy.Services;

/// <summary>
/// JSON response models for the license API.
/// </summary>
internal class LicenseVerifyResponse
{
    [JsonPropertyName("valid")]
    public bool Valid { get; set; }

    [JsonPropertyName("license")]
    public LicenseInfo? License { get; set; }

    [JsonPropertyName("error")]
    public string? Error { get; set; }
}

internal class LicenseActivateResponse
{
    [JsonPropertyName("activated")]
    public bool Activated { get; set; }

    [JsonPropertyName("message")]
    public string? Message { get; set; }

    [JsonPropertyName("error")]
    public string? Error { get; set; }
}

internal class LicenseInfo
{
    [JsonPropertyName("status")]
    public string Status { get; set; } = "";

    [JsonPropertyName("license_type")]
    public string LicenseType { get; set; } = "";

    [JsonPropertyName("expires_at")]
    public string ExpiresAt { get; set; } = "";
}

/// <summary>
/// Singleton license manager handling activation, verification, and deactivation
/// against the speechy.frkn.com.tr API. Implements INotifyPropertyChanged for WPF binding.
/// Matches the macOS LicenseManager behavior.
/// </summary>
public sealed class LicenseManager : INotifyPropertyChanged
{
    private static readonly Lazy<LicenseManager> _instance = new(() => new LicenseManager());
    public static LicenseManager Instance => _instance.Value;

    public event PropertyChangedEventHandler? PropertyChanged;

    private const string BaseUrl = "https://speechy.frkn.com.tr";
    private const string AppPlatform = "windows";
    private const string AppVersion = "1.0.0";
    private const double VerifyIntervalSeconds = 86400; // 24 hours

    private readonly HttpClient _httpClient;

    private bool _isLicensed;
    private string _licenseStatus = "";
    private string _licenseType = "";
    private string _expiresAt = "";

    private LicenseManager()
    {
        _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(15)
        };

        // Load cached license status for offline startup
        var settings = SettingsManager.Instance;
        if (settings.StoredLicenseKey != null)
        {
            _isLicensed = settings.CachedLicenseStatus;
        }
    }

    public bool IsLicensed
    {
        get => _isLicensed;
        private set { _isLicensed = value; OnPropertyChanged(); }
    }

    public string LicenseStatus
    {
        get => _licenseStatus;
        private set { _licenseStatus = value; OnPropertyChanged(); }
    }

    public string LicenseType
    {
        get => _licenseType;
        private set { _licenseType = value; OnPropertyChanged(); }
    }

    public string ExpiresAt
    {
        get => _expiresAt;
        private set { _expiresAt = value; OnPropertyChanged(); }
    }

    public string? StoredLicenseKey
    {
        get => SettingsManager.Instance.StoredLicenseKey;
        private set
        {
            SettingsManager.Instance.StoredLicenseKey = value;
            if (value == null)
            {
                IsLicensed = false;
                LicenseStatus = "";
            }
        }
    }

    /// <summary>
    /// Verifies a license key and activates it on this machine.
    /// Returns (success, message).
    /// </summary>
    public async Task<(bool Success, string Message)> Activate(string licenseKey)
    {
        try
        {
            // Step 1: Verify the license
            var verifyPayload = new { license_key = licenseKey };
            var verifyResponse = await _httpClient.PostAsJsonAsync($"{BaseUrl}/api/license/verify", verifyPayload);
            var verifyJson = await verifyResponse.Content.ReadAsStringAsync();
            var verifyResult = JsonSerializer.Deserialize<LicenseVerifyResponse>(verifyJson);

            if (verifyResult == null)
                return (false, "Invalid server response.");

            if (!string.IsNullOrEmpty(verifyResult.Error))
                return (false, verifyResult.Error);

            if (!verifyResult.Valid || verifyResult.License?.Status != "active")
            {
                var status = verifyResult.License?.Status ?? "invalid";
                return (false, $"License is {status}.");
            }

            // Step 2: Activate on this machine
            var activatePayload = new
            {
                license_key = licenseKey,
                machine_id = MachineIdProvider.GetMachineId(),
                machine_label = MachineIdProvider.GetMachineName(),
                app_platform = AppPlatform,
                app_version = AppVersion
            };

            var activateResponse = await _httpClient.PostAsJsonAsync($"{BaseUrl}/api/license/activate", activatePayload);
            var activateJson = await activateResponse.Content.ReadAsStringAsync();
            var activateResult = JsonSerializer.Deserialize<LicenseActivateResponse>(activateJson);

            if (activateResult == null)
                return (false, "Invalid server response.");

            if (!string.IsNullOrEmpty(activateResult.Error))
                return (false, activateResult.Error);

            if (activateResult.Activated)
            {
                StoredLicenseKey = licenseKey;
                var settings = SettingsManager.Instance;
                settings.CachedLicenseStatus = true;
                settings.LastLicenseVerified = DateTimeOffset.UtcNow.ToUnixTimeSeconds();

                IsLicensed = true;
                LicenseStatus = verifyResult.License!.Status;
                LicenseType = verifyResult.License.LicenseType;
                ExpiresAt = verifyResult.License.ExpiresAt;

                var msg = activateResult.Message ?? "Activated";
                Log.Info($"License activated: {msg}");
                return (true, msg);
            }

            return (false, "Activation failed.");
        }
        catch (TaskCanceledException)
        {
            return (false, "Connection timed out. Check your internet.");
        }
        catch (HttpRequestException ex)
        {
            Log.Error("License activation network error", ex);
            return (false, "Connection failed. Check your internet.");
        }
        catch (Exception ex)
        {
            Log.Error("License activation error", ex);
            return (false, $"Error: {ex.Message}");
        }
    }

    /// <summary>
    /// Verifies the stored license key with the server.
    /// Returns true if the license is still valid.
    /// </summary>
    public async Task<bool> Verify()
    {
        var key = StoredLicenseKey;
        if (string.IsNullOrEmpty(key)) return false;

        try
        {
            var payload = new { license_key = key };
            var response = await _httpClient.PostAsJsonAsync($"{BaseUrl}/api/license/verify", payload);
            var json = await response.Content.ReadAsStringAsync();
            var result = JsonSerializer.Deserialize<LicenseVerifyResponse>(json);

            if (result?.Valid == true)
            {
                var settings = SettingsManager.Instance;
                settings.LastLicenseVerified = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
                settings.CachedLicenseStatus = true;

                if (result.License != null)
                {
                    LicenseType = result.License.LicenseType;
                    ExpiresAt = result.License.ExpiresAt;
                    LicenseStatus = result.License.Status;
                }

                IsLicensed = true;
                return true;
            }
            else
            {
                Log.Info("License no longer valid, revoking");
                IsLicensed = false;
                SettingsManager.Instance.CachedLicenseStatus = false;
                return false;
            }
        }
        catch (Exception ex)
        {
            Log.Error("License verify error", ex);
            // On network failure, keep cached status
            return IsLicensed;
        }
    }

    /// <summary>
    /// Verifies the license in the background, only if 24 hours have elapsed since last check.
    /// </summary>
    public async Task VerifyInBackground()
    {
        var key = StoredLicenseKey;
        if (string.IsNullOrEmpty(key)) return;

        var lastVerified = SettingsManager.Instance.LastLicenseVerified;
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();

        if (now - lastVerified < VerifyIntervalSeconds) return;

        await Verify();
    }

    /// <summary>
    /// Deactivates the license on the server and clears local state.
    /// </summary>
    public async Task Deactivate()
    {
        var key = StoredLicenseKey;
        if (string.IsNullOrEmpty(key)) return;

        try
        {
            var payload = new
            {
                license_key = key,
                machine_id = MachineIdProvider.GetMachineId()
            };
            await _httpClient.PostAsJsonAsync($"{BaseUrl}/api/license/deactivate", payload);
            Log.Info("License deactivated on server");
        }
        catch (Exception ex)
        {
            Log.Error("License deactivate error", ex);
        }

        StoredLicenseKey = null;
        SettingsManager.Instance.CachedLicenseStatus = false;
        IsLicensed = false;
        LicenseStatus = "";
        LicenseType = "";
        ExpiresAt = "";
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
