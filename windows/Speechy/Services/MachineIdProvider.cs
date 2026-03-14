using System.Management;
using Microsoft.Win32;

namespace Speechy.Services;

/// <summary>
/// Provides a unique machine identifier using WMI Win32_ComputerSystemProduct UUID,
/// with a fallback to the Windows Registry MachineGuid.
/// </summary>
public static class MachineIdProvider
{
    private static string? _cachedId;

    /// <summary>
    /// Gets a unique, persistent machine identifier.
    /// Primary: WMI Win32_ComputerSystemProduct UUID.
    /// Fallback: Registry MachineGuid from HKLM\SOFTWARE\Microsoft\Cryptography.
    /// </summary>
    public static string GetMachineId()
    {
        if (_cachedId != null) return _cachedId;

        // Try WMI first
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT UUID FROM Win32_ComputerSystemProduct");
            foreach (var obj in searcher.Get())
            {
                var uuid = obj["UUID"]?.ToString();
                if (!string.IsNullOrWhiteSpace(uuid) &&
                    uuid != "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF" &&
                    uuid != "00000000-0000-0000-0000-000000000000")
                {
                    _cachedId = uuid;
                    Log.Info($"Machine ID from WMI: {uuid}");
                    return uuid;
                }
            }
        }
        catch (Exception ex)
        {
            Log.Error("Failed to get WMI UUID", ex);
        }

        // Fallback: Registry MachineGuid
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Cryptography");
            var guid = key?.GetValue("MachineGuid")?.ToString();
            if (!string.IsNullOrWhiteSpace(guid))
            {
                _cachedId = guid;
                Log.Info($"Machine ID from Registry: {guid}");
                return guid;
            }
        }
        catch (Exception ex)
        {
            Log.Error("Failed to get Registry MachineGuid", ex);
        }

        // Last resort: generate and persist a GUID
        var appDataPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Speechy", "machine_id");

        try
        {
            if (File.Exists(appDataPath))
            {
                var savedId = File.ReadAllText(appDataPath).Trim();
                if (!string.IsNullOrWhiteSpace(savedId))
                {
                    _cachedId = savedId;
                    return savedId;
                }
            }
        }
        catch { }

        var newId = Guid.NewGuid().ToString();
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(appDataPath)!);
            File.WriteAllText(appDataPath, newId);
        }
        catch { }

        _cachedId = newId;
        Log.Info($"Machine ID generated: {newId}");
        return newId;
    }

    /// <summary>
    /// Gets the machine's display name (computer name).
    /// </summary>
    public static string GetMachineName()
    {
        return Environment.MachineName;
    }
}
