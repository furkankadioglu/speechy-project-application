using System.Diagnostics;
using System.Windows;
using System.Windows.Media;

namespace Speechy.Views;

/// <summary>
/// Permission check window matching macOS PermissionCheckView.
/// Shows microphone and keyboard access status with colored indicators.
/// On Windows, microphone permission is managed by OS privacy settings;
/// keyboard hooks don't require special permissions but we show the status.
/// </summary>
public partial class PermissionCheckWindow : Window
{
    private bool _micGranted;
    private bool _keyboardGranted;

    public PermissionCheckWindow()
    {
        InitializeComponent();
        Loaded += (_, _) => CheckPermissions();
    }

    private void CheckPermissions()
    {
        // On Windows, microphone access is typically granted unless blocked in privacy settings.
        // We check if we can enumerate audio capture devices.
        _micGranted = CheckMicrophoneAccess();

        // Keyboard hook doesn't need special permission on Windows (it's an API call),
        // but we treat it as always granted for display purposes.
        _keyboardGranted = true;

        UpdateUI();
    }

    private bool CheckMicrophoneAccess()
    {
        try
        {
            // Try to enumerate audio capture devices using NAudio
            var enumerator = new NAudio.CoreAudioApi.MMDeviceEnumerator();
            var devices = enumerator.EnumerateAudioEndPoints(
                NAudio.CoreAudioApi.DataFlow.Capture,
                NAudio.CoreAudioApi.DeviceState.Active);
            return devices.Count > 0;
        }
        catch
        {
            return false;
        }
    }

    private void UpdateUI()
    {
        var greenBrush = new SolidColorBrush(Color.FromRgb(0x22, 0xC5, 0x5E));
        var redBrush = new SolidColorBrush(Color.FromRgb(0xEF, 0x44, 0x44));
        var greenBgBrush = new SolidColorBrush(Color.FromArgb(0x1A, 0x22, 0xC5, 0x5E));
        var redBgBrush = new SolidColorBrush(Color.FromArgb(0x1A, 0xEF, 0x44, 0x44));

        // Microphone
        MicIconBg.Fill = _micGranted ? greenBgBrush : redBgBrush;
        MicIcon.Text = _micGranted ? "\uE73E" : "\uE711"; // checkmark or X
        MicIcon.Foreground = _micGranted ? greenBrush : redBrush;
        MicBadge.Background = _micGranted ? greenBgBrush : redBgBrush;
        MicBadgeText.Text = _micGranted ? "Granted" : "Missing";
        MicBadgeText.Foreground = _micGranted ? greenBrush : redBrush;

        // Keyboard
        KeyboardIconBg.Fill = _keyboardGranted ? greenBgBrush : redBgBrush;
        KeyboardIcon.Text = _keyboardGranted ? "\uE73E" : "\uE711";
        KeyboardIcon.Foreground = _keyboardGranted ? greenBrush : redBrush;
        KeyboardBadge.Background = _keyboardGranted ? greenBgBrush : redBgBrush;
        KeyboardBadgeText.Text = _keyboardGranted ? "Granted" : "Missing";
        KeyboardBadgeText.Foreground = _keyboardGranted ? greenBrush : redBrush;

        // Buttons
        bool allGranted = _micGranted && _keyboardGranted;
        OpenSettingsButton.Visibility = allGranted ? Visibility.Collapsed : Visibility.Visible;
        ContinueButton.Visibility = allGranted ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OpenSettings_Click(object sender, RoutedEventArgs e)
    {
        // Open Windows Privacy Settings for Microphone
        Process.Start(new ProcessStartInfo("ms-settings:privacy-microphone")
        {
            UseShellExecute = true
        });
    }

    private void CheckAgain_Click(object sender, RoutedEventArgs e)
    {
        CheckPermissions();
    }

    private void Continue_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = true;
        Close();
    }
}
