using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using Speechy.Services;

namespace Speechy.Views.Controls;

/// <summary>
/// Custom waveform visualization control matching the macOS WaveformView.
/// 11 gradient bars (blue-to-purple) with weighted heights based on audio level.
/// Bar width: 4px, spacing: 2.5px, corner radius: 2.
/// </summary>
public partial class WaveformControl : UserControl
{
    private const int BarCount = 11;
    private const double BarWidth = 4;
    private const double BarSpacing = 2.5;

    private static readonly float[] Weights = { 0.3f, 0.4f, 0.55f, 0.7f, 0.85f, 1.0f, 0.85f, 0.7f, 0.55f, 0.4f, 0.3f };

    private readonly Rectangle[] _bars = new Rectangle[BarCount];
    private readonly Color _brandBlue = Color.FromRgb(0x00, 0x7A, 0xFF);    // #007AFF
    private readonly Color _brandPurple = Color.FromRgb(0xAF, 0x52, 0xDE);  // #AF52DE

    private float _currentLevel;

    public WaveformControl()
    {
        InitializeComponent();
        Loaded += (_, _) => SetupBars();
    }

    private void SetupBars()
    {
        WaveformCanvas.Children.Clear();

        double totalWidth = BarCount * BarWidth + (BarCount - 1) * BarSpacing;
        double startX = (ActualWidth > 0 ? ActualWidth : 100 - totalWidth) / 2;
        double canvasHeight = ActualHeight > 0 ? ActualHeight : 28;

        for (int i = 0; i < BarCount; i++)
        {
            var bar = new Rectangle
            {
                Width = BarWidth,
                Height = 3,
                RadiusX = 2,
                RadiusY = 2,
                Fill = new LinearGradientBrush(_brandBlue, _brandPurple, 90),
                Effect = new System.Windows.Media.Effects.DropShadowEffect
                {
                    Color = _brandBlue,
                    BlurRadius = 3,
                    ShadowDepth = 0,
                    Opacity = 0.4
                }
            };

            double x = startX + i * (BarWidth + BarSpacing);
            double y = (canvasHeight - 3) / 2;

            Canvas.SetLeft(bar, x);
            Canvas.SetTop(bar, y);
            WaveformCanvas.Children.Add(bar);
            _bars[i] = bar;
        }
    }

    /// <summary>
    /// Updates the waveform bars based on the current audio level (0.0-1.0+).
    /// </summary>
    public void UpdateLevel(float level)
    {
        _currentLevel = level;
        double canvasHeight = ActualHeight > 0 ? ActualHeight : 28;
        double divisor = SettingsManager.Instance.WaveDivisor;

        for (int i = 0; i < BarCount; i++)
        {
            if (_bars[i] == null) continue;

            double normalized = Math.Min(level * Weights[i] / divisor, 1.0);
            double height = Math.Max(normalized * canvasHeight, 3);
            double y = (canvasHeight - height) / 2;

            // Animate the height change
            var heightAnim = new DoubleAnimation(height, TimeSpan.FromMilliseconds(120))
            {
                EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
            };
            _bars[i].BeginAnimation(HeightProperty, heightAnim);
            Canvas.SetTop(_bars[i], y);

            // Blend gradient based on height ratio
            double ratio = height / canvasHeight;
            var midColor = Color.FromRgb(
                (byte)(_brandBlue.R * (1 - ratio) + _brandPurple.R * ratio),
                (byte)(_brandBlue.G * (1 - ratio) + _brandPurple.G * ratio),
                (byte)(_brandBlue.B * (1 - ratio) + _brandPurple.B * ratio));
            _bars[i].Fill = new LinearGradientBrush(_brandBlue, midColor, 90);
        }
    }

    /// <summary>
    /// Resets all bars to minimum height.
    /// </summary>
    public void Reset()
    {
        _currentLevel = 0;
        UpdateLevel(0);
    }
}
