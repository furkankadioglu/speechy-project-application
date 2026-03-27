using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using Speechy.Models;

namespace Speechy.Services;

/// <summary>
/// Persisted settings data structure for JSON serialization.
/// </summary>
public class SettingsData
{
    public HotkeyConfig Slot1 { get; set; } = new(ModifierKeys.Alt, "en");
    public HotkeyConfig Slot2 { get; set; } = new(ModifierKeys.Shift, "tr");
    public HotkeyConfig Slot3 { get; set; } = new(ModifierKeys.Ctrl, "en", true, HotkeyMode.ToggleToTalk);
    public HotkeyConfig Slot4 { get; set; } = new(ModifierKeys.Ctrl | ModifierKeys.Shift, "tr", true, HotkeyMode.ToggleToTalk);
    public double ActivationDelay { get; set; } = 0.15;
    public string SelectedModel { get; set; } = "base";
    public List<TranscriptionEntry> History { get; set; } = new();
    public string SelectedInputDeviceId { get; set; } = "system_default";
    public bool HasCompletedOnboarding { get; set; } = false;
    public bool LaunchAtLogin { get; set; } = false;
    public double WaveMultiplier { get; set; } = 100.0;
    public double WaveExponent { get; set; } = 0.45;
    public double WaveDivisor { get; set; } = 1.0;
    public bool PauseMediaDuringRecording { get; set; } = true;
    public List<string> SavedWords { get; set; } = new();
    public string ModalConfig { get; set; } = "default";
    public string? StoredLicenseKey { get; set; }
    public bool CachedLicenseStatus { get; set; } = false;
    public double LastLicenseVerified { get; set; } = 0;
}

/// <summary>
/// Singleton settings manager that persists to %APPDATA%/Speechy/settings.json.
/// All properties match the macOS SettingsManager. Implements INotifyPropertyChanged for WPF binding.
/// </summary>
public sealed class SettingsManager : INotifyPropertyChanged
{
    private static readonly Lazy<SettingsManager> _instance = new(() => new SettingsManager());
    public static SettingsManager Instance => _instance.Value;

    public event PropertyChangedEventHandler? PropertyChanged;
    public event Action? SettingsChanged;

    private readonly string _settingsDir;
    private readonly string _settingsPath;
    private readonly JsonSerializerOptions _jsonOptions;
    private bool _isSaving;

    private HotkeyConfig _slot1 = null!;
    private HotkeyConfig _slot2 = null!;
    private HotkeyConfig _slot3 = null!;
    private HotkeyConfig _slot4 = null!;
    private double _activationDelay;
    private WhisperModel _selectedModel;
    private List<TranscriptionEntry> _history = null!;
    private string _selectedInputDeviceId = null!;
    private bool _hasCompletedOnboarding;
    private bool _launchAtLogin;
    private double _waveMultiplier;
    private double _waveExponent;
    private double _waveDivisor;
    private bool _pauseMediaDuringRecording;
    private List<string> _savedWords = new();
    private Models.ModalConfig _modalConfig;

    private SettingsManager()
    {
        _settingsDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Speechy");
        Directory.CreateDirectory(_settingsDir);
        _settingsPath = Path.Combine(_settingsDir, "settings.json");

        _jsonOptions = new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            Converters = { new JsonStringEnumConverter() }
        };

        Load();
    }

    // --- Slot Properties ---

    public HotkeyConfig Slot1
    {
        get => _slot1;
        set { _slot1 = value; OnPropertyChanged(); SaveDebounced(); }
    }

    public HotkeyConfig Slot2
    {
        get => _slot2;
        set { _slot2 = value; OnPropertyChanged(); SaveDebounced(); }
    }

    public HotkeyConfig Slot3
    {
        get => _slot3;
        set { _slot3 = value; OnPropertyChanged(); SaveDebounced(); }
    }

    public HotkeyConfig Slot4
    {
        get => _slot4;
        set { _slot4 = value; OnPropertyChanged(); SaveDebounced(); }
    }

    // --- Audio/Recording Properties ---

    public double ActivationDelay
    {
        get => _activationDelay;
        set { _activationDelay = value; OnPropertyChanged(); SaveDebounced(); }
    }

    public WhisperModel SelectedModel
    {
        get => _selectedModel;
        set { _selectedModel = value; OnPropertyChanged(); SaveDebounced(); }
    }

    public string SelectedInputDeviceId
    {
        get => _selectedInputDeviceId;
        set { _selectedInputDeviceId = value; OnPropertyChanged(); SaveDebounced(); }
    }

    public bool PauseMediaDuringRecording
    {
        get => _pauseMediaDuringRecording;
        set { _pauseMediaDuringRecording = value; OnPropertyChanged(); SaveDebounced(); }
    }

    public List<string> SavedWords
    {
        get => _savedWords;
        set { _savedWords = value; OnPropertyChanged(); SaveDebounced(); }
    }

    public Models.ModalConfig ModalConfig
    {
        get => _modalConfig;
        set { _modalConfig = value; OnPropertyChanged(); OnPropertyChanged(nameof(WhisperPrompt)); SaveDebounced(); }
    }

    /// <summary>
    /// Builds the whisper --prompt string from saved words + modal config hint.
    /// </summary>
    public string? WhisperPrompt
    {
        get
        {
            var parts = new List<string>();
            if (_savedWords.Count > 0)
                parts.Add(string.Join(", ", _savedWords));
            var hint = _modalConfig.PromptHint();
            if (!string.IsNullOrEmpty(hint))
                parts.Add(hint);
            return parts.Count > 0 ? string.Join(". ", parts) : null;
        }
    }

    // --- Waveform Visualization ---

    public double WaveMultiplier
    {
        get => _waveMultiplier;
        set { _waveMultiplier = value; OnPropertyChanged(); SaveDebounced(); }
    }

    public double WaveExponent
    {
        get => _waveExponent;
        set { _waveExponent = value; OnPropertyChanged(); SaveDebounced(); }
    }

    public double WaveDivisor
    {
        get => _waveDivisor;
        set { _waveDivisor = value; OnPropertyChanged(); SaveDebounced(); }
    }

    // --- App State ---

    public List<TranscriptionEntry> History
    {
        get => _history;
        set { _history = value; OnPropertyChanged(); }
    }

    public bool HasCompletedOnboarding
    {
        get => _hasCompletedOnboarding;
        set { _hasCompletedOnboarding = value; OnPropertyChanged(); SaveDebounced(); }
    }

    public bool LaunchAtLogin
    {
        get => _launchAtLogin;
        set
        {
            _launchAtLogin = value;
            OnPropertyChanged();
            SaveDebounced();
            SetLaunchAtLogin(value);
        }
    }

    // --- License key stored alongside settings ---

    public string? StoredLicenseKey
    {
        get
        {
            var data = LoadRawData();
            return data?.StoredLicenseKey;
        }
        set
        {
            var data = LoadRawData() ?? new SettingsData();
            data.StoredLicenseKey = value;
            SaveRawData(data);
        }
    }

    public bool CachedLicenseStatus
    {
        get
        {
            var data = LoadRawData();
            return data?.CachedLicenseStatus ?? false;
        }
        set
        {
            var data = LoadRawData() ?? new SettingsData();
            data.CachedLicenseStatus = value;
            SaveRawData(data);
        }
    }

    public double LastLicenseVerified
    {
        get
        {
            var data = LoadRawData();
            return data?.LastLicenseVerified ?? 0;
        }
        set
        {
            var data = LoadRawData() ?? new SettingsData();
            data.LastLicenseVerified = value;
            SaveRawData(data);
        }
    }

    /// <summary>
    /// Gets the app data directory path.
    /// </summary>
    public string AppDataDirectory => _settingsDir;

    // --- History Management ---

    /// <summary>
    /// Adds a transcription to history, filtering blank audio and very short texts.
    /// Keeps max 50 entries, most recent first.
    /// </summary>
    public void AddToHistory(string text, string language)
    {
        if (text.Contains("[BLANK_AUDIO]") || text.Length < 2) return;

        var entry = new TranscriptionEntry(text, language);
        _history.Insert(0, entry);
        if (_history.Count > 50)
        {
            _history = _history.Take(50).ToList();
        }
        OnPropertyChanged(nameof(History));
        Save();
    }

    /// <summary>
    /// Clears all transcription history.
    /// </summary>
    public void ClearHistory()
    {
        _history.Clear();
        OnPropertyChanged(nameof(History));
        Save();
    }

    // --- Persistence ---

    private CancellationTokenSource? _saveDebounce;

    private void SaveDebounced()
    {
        _saveDebounce?.Cancel();
        _saveDebounce = new CancellationTokenSource();
        var token = _saveDebounce.Token;

        Task.Delay(100, token).ContinueWith(_ =>
        {
            if (!token.IsCancellationRequested)
            {
                Save();
                SettingsChanged?.Invoke();
            }
        }, TaskScheduler.Default);
    }

    /// <summary>
    /// Saves current settings to disk immediately.
    /// </summary>
    public void Save()
    {
        if (_isSaving) return;
        _isSaving = true;

        try
        {
            var data = new SettingsData
            {
                Slot1 = _slot1,
                Slot2 = _slot2,
                Slot3 = _slot3,
                Slot4 = _slot4,
                ActivationDelay = _activationDelay,
                SelectedModel = _selectedModel.RawValue(),
                History = _history,
                SelectedInputDeviceId = _selectedInputDeviceId,
                HasCompletedOnboarding = _hasCompletedOnboarding,
                LaunchAtLogin = _launchAtLogin,
                WaveMultiplier = _waveMultiplier,
                WaveExponent = _waveExponent,
                WaveDivisor = _waveDivisor,
                PauseMediaDuringRecording = _pauseMediaDuringRecording,
                SavedWords = _savedWords,
                ModalConfig = _modalConfig.RawValue(),
            };

            // Preserve license data
            var existing = LoadRawData();
            if (existing != null)
            {
                data.StoredLicenseKey = existing.StoredLicenseKey;
                data.CachedLicenseStatus = existing.CachedLicenseStatus;
                data.LastLicenseVerified = existing.LastLicenseVerified;
            }

            var json = JsonSerializer.Serialize(data, _jsonOptions);
            File.WriteAllText(_settingsPath, json);
            Log.Info("Settings saved");
        }
        catch (Exception ex)
        {
            Log.Error("Failed to save settings", ex);
        }
        finally
        {
            _isSaving = false;
        }
    }

    /// <summary>
    /// Loads settings from disk, applying defaults for any missing values.
    /// </summary>
    public void Load()
    {
        try
        {
            var data = LoadRawData() ?? new SettingsData();

            _slot1 = data.Slot1;
            _slot2 = data.Slot2;
            _slot3 = data.Slot3;
            _slot4 = data.Slot4;
            _activationDelay = data.ActivationDelay == 0 ? 0.15 : data.ActivationDelay;
            _selectedModel = WhisperModelExtensions.FromRawValue(data.SelectedModel);
            _history = data.History ?? new List<TranscriptionEntry>();
            _selectedInputDeviceId = data.SelectedInputDeviceId ?? "system_default";
            _hasCompletedOnboarding = data.HasCompletedOnboarding;
            _launchAtLogin = data.LaunchAtLogin;
            _waveMultiplier = data.WaveMultiplier == 0 ? 100.0 : data.WaveMultiplier;
            _waveExponent = data.WaveExponent == 0 ? 0.45 : data.WaveExponent;
            _waveDivisor = data.WaveDivisor == 0 ? 1.0 : data.WaveDivisor;
            _pauseMediaDuringRecording = data.PauseMediaDuringRecording;
            _savedWords = data.SavedWords ?? new List<string>();
            _modalConfig = Models.ModalConfigExtensions.FromRawValue(data.ModalConfig);

            Log.Info("Settings loaded");
        }
        catch (Exception ex)
        {
            Log.Error("Failed to load settings, using defaults", ex);
            ApplyDefaults();
        }
    }

    private SettingsData? LoadRawData()
    {
        try
        {
            if (!File.Exists(_settingsPath)) return null;
            var json = File.ReadAllText(_settingsPath);
            return JsonSerializer.Deserialize<SettingsData>(json, _jsonOptions);
        }
        catch
        {
            return null;
        }
    }

    private void SaveRawData(SettingsData data)
    {
        try
        {
            var json = JsonSerializer.Serialize(data, _jsonOptions);
            File.WriteAllText(_settingsPath, json);
        }
        catch (Exception ex)
        {
            Log.Error("Failed to save raw data", ex);
        }
    }

    private void ApplyDefaults()
    {
        _slot1 = new HotkeyConfig(ModifierKeys.Alt, "en");
        _slot2 = new HotkeyConfig(ModifierKeys.Shift, "tr");
        _slot3 = new HotkeyConfig(ModifierKeys.Ctrl, "en", true, HotkeyMode.ToggleToTalk);
        _slot4 = new HotkeyConfig(ModifierKeys.Ctrl | ModifierKeys.Shift, "tr", true, HotkeyMode.ToggleToTalk);
        _activationDelay = 0.15;
        _selectedModel = WhisperModel.Fast;
        _history = new List<TranscriptionEntry>();
        _selectedInputDeviceId = "system_default";
        _hasCompletedOnboarding = false;
        _launchAtLogin = false;
        _waveMultiplier = 100.0;
        _waveExponent = 0.45;
        _waveDivisor = 1.0;
        _pauseMediaDuringRecording = true;
    }

    private void SetLaunchAtLogin(bool enabled)
    {
        try
        {
            var keyPath = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(keyPath, true);
            if (key == null) return;

            if (enabled)
            {
                var exePath = System.Diagnostics.Process.GetCurrentProcess().MainModule?.FileName;
                if (exePath != null)
                {
                    key.SetValue("Speechy", $"\"{exePath}\"");
                }
            }
            else
            {
                key.DeleteValue("Speechy", false);
            }
            Log.Info($"Launch at login set to: {enabled}");
        }
        catch (Exception ex)
        {
            Log.Error("Failed to set launch at login", ex);
        }
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
