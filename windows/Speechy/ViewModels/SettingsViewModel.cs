using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using Speechy.Helpers;
using Speechy.Models;
using Speechy.Services;

namespace Speechy.ViewModels;

/// <summary>
/// ViewModel wrapping SettingsManager, ModelDownloadManager, and LicenseManager for WPF data binding.
/// Provides commands for all user interactions in the Settings window.
/// </summary>
public class SettingsViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    private readonly SettingsManager _settings;
    private readonly ModelDownloadManager _downloadManager;
    private readonly LicenseManager _licenseManager;

    public SettingsViewModel()
    {
        _settings = SettingsManager.Instance;
        _downloadManager = ModelDownloadManager.Instance;
        _licenseManager = LicenseManager.Instance;

        // Forward property changes
        _settings.PropertyChanged += (_, e) =>
        {
            OnPropertyChanged(e.PropertyName ?? "");
            // Also notify computed properties
            if (e.PropertyName == nameof(SettingsManager.History))
            {
                OnPropertyChanged(nameof(HistoryCount));
                OnPropertyChanged(nameof(HasHistory));
            }
        };

        _downloadManager.PropertyChanged += (_, e) =>
        {
            OnPropertyChanged($"Download_{e.PropertyName}");
            OnPropertyChanged(nameof(IsDownloading));
            OnPropertyChanged(nameof(DownloadProgress));
            OnPropertyChanged(nameof(DownloadStatus));
            OnPropertyChanged(nameof(CurrentlyDownloading));
        };

        _licenseManager.PropertyChanged += (_, e) =>
        {
            OnPropertyChanged($"License_{e.PropertyName}");
            OnPropertyChanged(nameof(IsLicensed));
            OnPropertyChanged(nameof(LicenseStatus));
            OnPropertyChanged(nameof(LicenseType));
            OnPropertyChanged(nameof(ExpiresAt));
            OnPropertyChanged(nameof(MaskedLicenseKey));
            OnPropertyChanged(nameof(PlanLabel));
        };

        // Commands
        ClearHistoryCommand = new RelayCommand(() => _settings.ClearHistory());
        DeleteHistoryEntryCommand = new RelayCommand(param =>
        {
            if (param is TranscriptionEntry entry)
            {
                _settings.History.Remove(entry);
                _settings.Save();
                OnPropertyChanged(nameof(History));
                OnPropertyChanged(nameof(HistoryCount));
                OnPropertyChanged(nameof(HasHistory));
            }
        });

        CopyTextCommand = new RelayCommand(param =>
        {
            if (param is string text)
            {
                System.Windows.Clipboard.SetText(text);
            }
        });

        DownloadModelCommand = new AsyncRelayCommand(async param =>
        {
            if (param is WhisperModel model)
            {
                await _downloadManager.DownloadModel(model);
                OnPropertyChanged(nameof(IsModelDownloaded));
            }
        });

        SelectModelCommand = new RelayCommand(param =>
        {
            if (param is WhisperModel model && _downloadManager.ModelExists(model))
            {
                SelectedModel = model;
            }
        });

        DeactivateLicenseCommand = new AsyncRelayCommand(async () =>
        {
            await _licenseManager.Deactivate();
        });

        Languages = new ObservableCollection<SupportedLanguage>(SupportedLanguages.All);
        Models = new ObservableCollection<WhisperModel>(
            Enum.GetValues<WhisperModel>());
    }

    // --- Collections ---

    public ObservableCollection<SupportedLanguage> Languages { get; }
    public ObservableCollection<WhisperModel> Models { get; }

    // --- Slot Properties (delegate to SettingsManager) ---

    public HotkeyConfig Slot1
    {
        get => _settings.Slot1;
        set { _settings.Slot1 = value; OnPropertyChanged(); }
    }

    public HotkeyConfig Slot2
    {
        get => _settings.Slot2;
        set { _settings.Slot2 = value; OnPropertyChanged(); }
    }

    public HotkeyConfig Slot3
    {
        get => _settings.Slot3;
        set { _settings.Slot3 = value; OnPropertyChanged(); }
    }

    public HotkeyConfig Slot4
    {
        get => _settings.Slot4;
        set { _settings.Slot4 = value; OnPropertyChanged(); }
    }

    // --- Model Selection ---

    public WhisperModel SelectedModel
    {
        get => _settings.SelectedModel;
        set { _settings.SelectedModel = value; OnPropertyChanged(); }
    }

    public bool IsModelDownloaded => _downloadManager.ModelExists(_settings.SelectedModel);

    public bool ModelExists(WhisperModel model) => _downloadManager.ModelExists(model);

    // --- Download Manager ---

    public bool IsDownloading => _downloadManager.IsDownloading;
    public double DownloadProgress => _downloadManager.DownloadProgress;
    public string DownloadStatus => _downloadManager.DownloadStatus;
    public WhisperModel? CurrentlyDownloading => _downloadManager.CurrentlyDownloading;

    // --- Audio Settings ---

    public double ActivationDelay
    {
        get => _settings.ActivationDelay;
        set { _settings.ActivationDelay = value; OnPropertyChanged(); OnPropertyChanged(nameof(ActivationDelayMs)); }
    }

    public int ActivationDelayMs => (int)(_settings.ActivationDelay * 1000);

    public string SelectedInputDeviceId
    {
        get => _settings.SelectedInputDeviceId;
        set { _settings.SelectedInputDeviceId = value; OnPropertyChanged(); }
    }

    // --- Waveform Settings ---

    public double WaveMultiplier
    {
        get => _settings.WaveMultiplier;
        set { _settings.WaveMultiplier = value; OnPropertyChanged(); }
    }

    public double WaveExponent
    {
        get => _settings.WaveExponent;
        set { _settings.WaveExponent = value; OnPropertyChanged(); }
    }

    public double WaveDivisor
    {
        get => _settings.WaveDivisor;
        set { _settings.WaveDivisor = value; OnPropertyChanged(); }
    }

    // --- General Settings ---

    public bool LaunchAtLogin
    {
        get => _settings.LaunchAtLogin;
        set { _settings.LaunchAtLogin = value; OnPropertyChanged(); }
    }

    public bool PauseMediaDuringRecording
    {
        get => _settings.PauseMediaDuringRecording;
        set { _settings.PauseMediaDuringRecording = value; OnPropertyChanged(); }
    }

    // --- History ---

    public List<TranscriptionEntry> History => _settings.History;
    public int HistoryCount => _settings.History.Count;
    public bool HasHistory => _settings.History.Count > 0;

    // --- License ---

    public bool IsLicensed => _licenseManager.IsLicensed;
    public string LicenseStatus => _licenseManager.LicenseStatus;
    public string LicenseType => _licenseManager.LicenseType;
    public string ExpiresAt => _licenseManager.ExpiresAt;

    public string MaskedLicenseKey
    {
        get
        {
            var key = _licenseManager.StoredLicenseKey ?? "";
            if (key.Length <= 8) return key;
            return $"{key[..4]}--------{key[^4..]}";
        }
    }

    public string PlanLabel => _licenseManager.LicenseType switch
    {
        "trial" => "Free Trial",
        "monthly" => "Monthly",
        "yearly" => "Annual",
        "lifetime" => "Lifetime",
        _ => string.IsNullOrEmpty(_licenseManager.LicenseType) ? "" : _licenseManager.LicenseType
    };

    public string MachineId => MachineIdProvider.GetMachineId();
    public string ShortMachineId => MachineId.Length > 16 ? MachineId[..16] + "..." : MachineId;

    // --- Commands ---

    public ICommand ClearHistoryCommand { get; }
    public ICommand DeleteHistoryEntryCommand { get; }
    public ICommand CopyTextCommand { get; }
    public ICommand DownloadModelCommand { get; }
    public ICommand SelectModelCommand { get; }
    public ICommand DeactivateLicenseCommand { get; }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
