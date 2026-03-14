using System.Diagnostics;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Speechy.Services;

namespace Speechy.Views;

/// <summary>
/// License activation window matching macOS LicenseView.
/// Blue-purple gradient circle with key icon, license key input,
/// activate button with spinner, error/success messages, and trial link.
/// </summary>
public partial class LicenseWindow : Window
{
    private DispatcherTimer? _spinnerTimer;

    /// <summary>
    /// True if the license was successfully activated.
    /// </summary>
    public bool IsActivated { get; private set; }

    public LicenseWindow()
    {
        InitializeComponent();
        LicenseKeyInput.TextChanged += (_, _) =>
        {
            ActivateButton.IsEnabled = !string.IsNullOrWhiteSpace(LicenseKeyInput.Text);
        };
    }

    private void LicenseKeyInput_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            ActivateLicense();
        }
    }

    private void ActivateButton_Click(object sender, RoutedEventArgs e)
    {
        ActivateLicense();
    }

    private async void ActivateLicense()
    {
        var key = LicenseKeyInput.Text.Trim();
        if (string.IsNullOrEmpty(key)) return;

        // Set loading state
        ActivateButton.IsEnabled = false;
        ActivateButtonText.Text = "Verifying...";
        ActivateSpinner.Visibility = Visibility.Visible;
        ErrorPanel.Visibility = Visibility.Collapsed;
        SuccessPanel.Visibility = Visibility.Collapsed;
        LicenseKeyInput.IsEnabled = false;
        StartSpinnerAnimation();

        var (success, message) = await LicenseManager.Instance.Activate(key);

        StopSpinnerAnimation();

        if (success)
        {
            SuccessPanel.Visibility = Visibility.Visible;
            IsActivated = true;

            // Auto-close after 1 second
            await Task.Delay(1000);
            DialogResult = true;
            Close();
        }
        else
        {
            ErrorText.Text = message;
            ErrorPanel.Visibility = Visibility.Visible;
            ActivateButton.IsEnabled = true;
            ActivateButtonText.Text = "Activate License";
            ActivateSpinner.Visibility = Visibility.Collapsed;
            LicenseKeyInput.IsEnabled = true;
        }
    }

    private void StartSpinnerAnimation()
    {
        var angle = 0.0;
        _spinnerTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(30) };
        _spinnerTimer.Tick += (_, _) =>
        {
            angle = (angle + 10) % 360;
            SpinnerRotation.Angle = angle;
        };
        _spinnerTimer.Start();
    }

    private void StopSpinnerAnimation()
    {
        _spinnerTimer?.Stop();
        _spinnerTimer = null;
    }

    private void TrialLink_Click(object sender, MouseButtonEventArgs e)
    {
        Process.Start(new ProcessStartInfo("https://speechy.frkn.com.tr")
        {
            UseShellExecute = true
        });
    }
}
