using System.Windows;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace Speechy.Views;

/// <summary>
/// Splash screen window matching the macOS SplashView.
/// Shows a gradient circle with mic icon, app name, animated progress bar.
/// Auto-closes after ~2 seconds of progress animation.
/// </summary>
public partial class SplashWindow : Window
{
    private readonly DispatcherTimer _timer;
    private double _progress;

    /// <summary>
    /// Fired when the splash animation completes.
    /// </summary>
    public event Action? OnSplashComplete;

    public SplashWindow()
    {
        InitializeComponent();

        _timer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(20)
        };
        _timer.Tick += Timer_Tick;
    }

    protected override void OnContentRendered(EventArgs e)
    {
        base.OnContentRendered(e);
        _timer.Start();
    }

    private void Timer_Tick(object? sender, EventArgs e)
    {
        _progress += 0.01;

        if (_progress >= 1.0)
        {
            _timer.Stop();
            ProgressFill.Width = 200;

            // Fade out
            var fadeOut = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(300))
            {
                EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
            };
            fadeOut.Completed += (_, _) =>
            {
                OnSplashComplete?.Invoke();
                Close();
            };
            BeginAnimation(OpacityProperty, fadeOut);
        }
        else
        {
            ProgressFill.Width = 200 * _progress;
        }
    }
}
