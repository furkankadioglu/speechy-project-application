using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using Speechy.Helpers;

namespace Speechy.ViewModels;

/// <summary>
/// ViewModel for the main SettingsWindow. Manages tab navigation and quit command.
/// </summary>
public class MainViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    private int _selectedTab;

    public MainViewModel()
    {
        SelectTabCommand = new RelayCommand(param =>
        {
            if (param is int tab)
                SelectedTab = tab;
            else if (param is string s && int.TryParse(s, out var parsed))
                SelectedTab = parsed;
        });

        QuitCommand = new RelayCommand(() =>
        {
            OnQuitRequested?.Invoke();
        });
    }

    /// <summary>
    /// Currently selected tab index: 0=Settings, 1=Advanced, 2=History, 3=License
    /// </summary>
    public int SelectedTab
    {
        get => _selectedTab;
        set
        {
            if (_selectedTab != value)
            {
                _selectedTab = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(IsSettingsTab));
                OnPropertyChanged(nameof(IsAdvancedTab));
                OnPropertyChanged(nameof(IsHistoryTab));
                OnPropertyChanged(nameof(IsLicenseTab));
            }
        }
    }

    public bool IsSettingsTab => _selectedTab == 0;
    public bool IsAdvancedTab => _selectedTab == 1;
    public bool IsHistoryTab => _selectedTab == 2;
    public bool IsLicenseTab => _selectedTab == 3;

    public ICommand SelectTabCommand { get; }
    public ICommand QuitCommand { get; }

    /// <summary>
    /// Event raised when the user clicks the Quit button.
    /// </summary>
    public event Action? OnQuitRequested;

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
