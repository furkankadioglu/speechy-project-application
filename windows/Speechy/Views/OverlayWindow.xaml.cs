using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;

namespace Speechy.Views;

/// <summary>
/// Transparent, always-on-top, click-through overlay window matching macOS OverlayWindow.
/// Shows recording state (icon + waveform) or processing state (spinner).
/// Positioned at bottom-center of screen. 120x150px with dark rounded background.
/// </summary>
public partial class OverlayWindow : Window
{
    public enum OverlayState { Hidden, Recording, Processing }

    private DispatcherTimer? _spinnerTimer;
    private double _spinnerAngle;

    // Win32 constants for click-through window
    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TRANSPARENT = 0x00000020;
    private const int WS_EX_TOOLWINDOW = 0x00000080;

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(IntPtr hwnd, int index);

    [DllImport("user32.dll")]
    private static extern int SetWindowLong(IntPtr hwnd, int index, int newStyle);

    public OverlayWindow()
    {
        InitializeComponent();
        PositionAtBottomCenter();
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        // Make window click-through and hide from taskbar/alt-tab
        var hwnd = new WindowInteropHelper(this).Handle;
        var extendedStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
        SetWindowLong(hwnd, GWL_EXSTYLE,
            extendedStyle | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW);
    }

    private void PositionAtBottomCenter()
    {
        var screen = SystemParameters.WorkArea;
        Left = screen.Left + (screen.Width - Width) / 2;
        Top = screen.Bottom - Height - 80;
    }

    /// <summary>
    /// Updates the waveform visualization with the current audio level.
    /// </summary>
    public void UpdateLevel(float level)
    {
        WaveformView.UpdateLevel(level);
    }

    /// <summary>
    /// Sets the overlay display state.
    /// </summary>
    /// <param name="state">The new state (Hidden, Recording, Processing).</param>
    /// <param name="flag">Optional flag emoji to display on the icon badge.</param>
    public void SetState(OverlayState state, string? flag = null)
    {
        Dispatcher.Invoke(() =>
        {
            switch (state)
            {
                case OverlayState.Hidden:
                    Hide();
                    StopSpinner();
                    SpeechyIconPanel.Visibility = Visibility.Collapsed;
                    WaveformView.Visibility = Visibility.Collapsed;
                    SpinnerPanel.Visibility = Visibility.Collapsed;
                    WaveformView.Reset();
                    break;

                case OverlayState.Recording:
                    StopSpinner();
                    SpinnerPanel.Visibility = Visibility.Collapsed;
                    SpeechyIconPanel.Visibility = Visibility.Visible;
                    WaveformView.Visibility = Visibility.Visible;

                    if (!string.IsNullOrEmpty(flag))
                    {
                        FlagText.Text = flag;
                        FlagBadge.Visibility = Visibility.Visible;
                    }
                    else
                    {
                        FlagBadge.Visibility = Visibility.Collapsed;
                    }

                    PositionAtBottomCenter();
                    Show();
                    break;

                case OverlayState.Processing:
                    SpeechyIconPanel.Visibility = Visibility.Collapsed;
                    WaveformView.Visibility = Visibility.Collapsed;
                    WaveformView.Reset();
                    SpinnerPanel.Visibility = Visibility.Visible;
                    StartSpinner();
                    PositionAtBottomCenter();
                    Show();
                    break;
            }
        });
    }

    private void StartSpinner()
    {
        if (_spinnerTimer != null) return;

        _spinnerAngle = 0;
        _spinnerTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(30)
        };
        _spinnerTimer.Tick += (_, _) =>
        {
            _spinnerAngle = (_spinnerAngle + 10) % 360;
            SpinnerTransform.Angle = _spinnerAngle;
        };
        _spinnerTimer.Start();
    }

    private void StopSpinner()
    {
        _spinnerTimer?.Stop();
        _spinnerTimer = null;
    }
}
