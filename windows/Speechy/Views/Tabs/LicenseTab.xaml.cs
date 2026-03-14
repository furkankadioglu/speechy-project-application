using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Speechy.Services;

namespace Speechy.Views.Tabs;

/// <summary>
/// License tab matching macOS LicenseTab.
/// Shows license status card, license details (key, plan, status, expires, machine ID),
/// deactivate button, and permissions section.
/// </summary>
public partial class LicenseTab : UserControl
{
    private readonly LicenseManager _licenseManager;

    public LicenseTab()
    {
        InitializeComponent();
        _licenseManager = LicenseManager.Instance;
        Loaded += (_, _) => RefreshUI();

        _licenseManager.PropertyChanged += (_, _) =>
        {
            Dispatcher.Invoke(RefreshUI);
        };
    }

    private void RefreshUI()
    {
        var isLicensed = _licenseManager.IsLicensed;

        var greenBrush = new SolidColorBrush(Color.FromRgb(0x22, 0xC5, 0x5E));
        var redBrush = new SolidColorBrush(Color.FromRgb(0xEF, 0x44, 0x44));

        // Status card
        if (isLicensed)
        {
            StatusCard.Background = new SolidColorBrush(Color.FromArgb(0x0D, 0x22, 0xC5, 0x5E));
            StatusCard.BorderBrush = new SolidColorBrush(Color.FromArgb(0x33, 0x22, 0xC5, 0x5E));
            StatusIconBg.Fill = new SolidColorBrush(Color.FromArgb(0x26, 0x22, 0xC5, 0x5E));
            StatusIcon.Text = "\uEB51"; // checkmark seal
            StatusIcon.Foreground = greenBrush;
            StatusTitle.Text = "License Active";
            StatusDescription.Text = "Your Speechy license is valid and active.";
        }
        else
        {
            StatusCard.Background = new SolidColorBrush(Color.FromArgb(0x0D, 0xEF, 0x44, 0x44));
            StatusCard.BorderBrush = new SolidColorBrush(Color.FromArgb(0x33, 0xEF, 0x44, 0x44));
            StatusIconBg.Fill = new SolidColorBrush(Color.FromArgb(0x26, 0xEF, 0x44, 0x44));
            StatusIcon.Text = "\uEB52"; // X seal
            StatusIcon.Foreground = redBrush;
            StatusTitle.Text = "No Active License";
            StatusDescription.Text = "Please activate a license to use Speechy.";
        }

        // Details and deactivate
        DetailsCard.Visibility = isLicensed ? Visibility.Visible : Visibility.Collapsed;
        DeactivateButton.Visibility = isLicensed ? Visibility.Visible : Visibility.Collapsed;

        if (isLicensed)
        {
            LicenseKeyText.Text = MaskKey(_licenseManager.StoredLicenseKey ?? "");
            PlanText.Text = GetPlanLabel(_licenseManager.LicenseType);
            LicenseStatusText.Text = string.IsNullOrEmpty(_licenseManager.LicenseStatus)
                ? "Active"
                : CultureInfo.CurrentCulture.TextInfo.ToTitleCase(_licenseManager.LicenseStatus);

            // Expires
            if (!string.IsNullOrEmpty(_licenseManager.ExpiresAt) && _licenseManager.LicenseType != "lifetime")
            {
                ExpiresDivider.Visibility = Visibility.Visible;
                ExpiresRow.Visibility = Visibility.Visible;
                ExpiresText.Text = FormatDate(_licenseManager.ExpiresAt);
            }
            else
            {
                ExpiresDivider.Visibility = Visibility.Collapsed;
                ExpiresRow.Visibility = Visibility.Collapsed;
            }

            // Machine ID
            var machineId = MachineIdProvider.GetMachineId();
            MachineIdText.Text = machineId.Length > 16 ? machineId[..16] + "..." : machineId;
        }

        // Permissions
        UpdatePermissions();
    }

    private void UpdatePermissions()
    {
        var greenBrush = new SolidColorBrush(Color.FromRgb(0x22, 0xC5, 0x5E));
        var redBrush = new SolidColorBrush(Color.FromRgb(0xEF, 0x44, 0x44));
        var greenBgBrush = new SolidColorBrush(Color.FromArgb(0x1A, 0x22, 0xC5, 0x5E));
        var redBgBrush = new SolidColorBrush(Color.FromArgb(0x1A, 0xEF, 0x44, 0x44));

        // Microphone
        bool micGranted = CheckMicrophoneAccess();
        MicPermIcon.Text = micGranted ? "\uE73E" : "\uE711";
        MicPermIcon.Foreground = micGranted ? greenBrush : redBrush;
        MicPermBadge.Background = micGranted ? greenBgBrush : redBgBrush;
        MicPermText.Text = micGranted ? "Granted" : "Missing";
        MicPermText.Foreground = micGranted ? greenBrush : redBrush;

        // Keyboard (always granted on Windows)
        KeyPermIcon.Text = "\uE73E";
        KeyPermIcon.Foreground = greenBrush;
        KeyPermBadge.Background = greenBgBrush;
        KeyPermText.Text = "Granted";
        KeyPermText.Foreground = greenBrush;
    }

    private bool CheckMicrophoneAccess()
    {
        try
        {
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

    private async void Deactivate_Click(object sender, RoutedEventArgs e)
    {
        var result = MessageBox.Show(
            "This will remove the license from this device. You can reactivate it later.",
            "Deactivate License?",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);

        if (result == MessageBoxResult.Yes)
        {
            await _licenseManager.Deactivate();
            RefreshUI();
        }
    }

    private static string MaskKey(string key)
    {
        if (key.Length <= 8) return key;
        return $"{key[..4]}--------{key[^4..]}";
    }

    private static string GetPlanLabel(string type) => type switch
    {
        "trial" => "Free Trial",
        "monthly" => "Monthly",
        "yearly" => "Annual",
        "lifetime" => "Lifetime",
        _ => string.IsNullOrEmpty(type) ? "" : CultureInfo.CurrentCulture.TextInfo.ToTitleCase(type)
    };

    private static string FormatDate(string dateStr)
    {
        if (DateTimeOffset.TryParse(dateStr, out var date))
        {
            return date.LocalDateTime.ToString("MMM d, yyyy");
        }
        return dateStr.Length > 10 ? dateStr[..10] : dateStr;
    }
}
