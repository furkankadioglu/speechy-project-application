using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using Speechy.Models;
using Speechy.Services;

namespace Speechy.Views.Tabs;

/// <summary>
/// Advanced tab matching macOS AdvancedTab.
/// Sections: AI Model selection, Activation Delay, Voice Input device,
/// Waveform Sensitivity sliders, General toggles.
/// </summary>
public partial class AdvancedTab : UserControl
{
    private readonly SettingsManager _settings;
    private readonly ModelDownloadManager _downloadManager;
    private bool _isInitialized;

    public AdvancedTab()
    {
        InitializeComponent();
        _settings = SettingsManager.Instance;
        _downloadManager = ModelDownloadManager.Instance;
        Loaded += (_, _) => Initialize();
    }

    private void Initialize()
    {
        if (_isInitialized) return;
        _isInitialized = true;

        // Initialize sliders
        DelaySlider.Value = _settings.ActivationDelay * 1000;
        DelayValueText.Text = $"{(int)(_settings.ActivationDelay * 1000)} ms";

        MultiplierSlider.Value = _settings.WaveMultiplier;
        MultiplierValueText.Text = $"{_settings.WaveMultiplier:F0}";

        ExponentSlider.Value = _settings.WaveExponent;
        ExponentValueText.Text = $"{_settings.WaveExponent:F2}";

        DivisorSlider.Value = _settings.WaveDivisor;
        DivisorValueText.Text = $"{_settings.WaveDivisor:F2}";

        // Toggles
        LaunchAtLoginToggle.IsChecked = _settings.LaunchAtLogin;
        PauseMediaToggle.IsChecked = _settings.PauseMediaDuringRecording;

        // Build model options
        BuildModelOptions();

        // Populate audio devices
        PopulateAudioDevices();

        // Listen for download changes
        _downloadManager.PropertyChanged += (_, e) =>
        {
            Dispatcher.Invoke(() =>
            {
                if (e.PropertyName == nameof(ModelDownloadManager.DownloadProgress) ||
                    e.PropertyName == nameof(ModelDownloadManager.IsDownloading) ||
                    e.PropertyName == nameof(ModelDownloadManager.DownloadStatus))
                {
                    BuildModelOptions();
                }
            });
        };
    }

    private void BuildModelOptions()
    {
        ModelOptionsPanel.Children.Clear();

        foreach (WhisperModel model in Enum.GetValues<WhisperModel>())
        {
            var isSelected = _settings.SelectedModel == model;
            var isDownloaded = _downloadManager.ModelExists(model);
            var isDownloading = _downloadManager.CurrentlyDownloading == model;

            var row = new Grid { Margin = new Thickness(0, 0, 0, 8) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Auto) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Auto) });

            // Radio circle
            var radioGrid = new Grid { Width = 22, Height = 22, Margin = new Thickness(0, 0, 12, 0) };
            var outerCircle = new Ellipse
            {
                Stroke = isSelected
                    ? new SolidColorBrush(Color.FromRgb(0x8B, 0x5C, 0xF6))
                    : new SolidColorBrush(Color.FromArgb(0x4D, 0xA0, 0xA0, 0xB8)),
                StrokeThickness = 2,
                Opacity = isDownloaded ? 1 : 0.3
            };
            radioGrid.Children.Add(outerCircle);
            if (isSelected)
            {
                radioGrid.Children.Add(new Ellipse
                {
                    Fill = new SolidColorBrush(Color.FromRgb(0x8B, 0x5C, 0xF6)),
                    Width = 14, Height = 14
                });
            }
            Grid.SetColumn(radioGrid, 0);
            row.Children.Add(radioGrid);

            // Model info
            var infoPanel = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            var nameRow = new StackPanel { Orientation = Orientation.Horizontal };
            nameRow.Children.Add(new TextBlock
            {
                Text = model.DisplayName(),
                FontSize = 13, FontWeight = FontWeights.SemiBold,
                Foreground = Brushes.White
            });

            if (!isDownloaded && !isDownloading)
            {
                var sizeBadge = new Border
                {
                    Background = new SolidColorBrush(Color.FromArgb(0x26, 0xA0, 0xA0, 0xB8)),
                    CornerRadius = new CornerRadius(4),
                    Padding = new Thickness(6, 2, 6, 2),
                    Margin = new Thickness(6, 0, 0, 0)
                };
                sizeBadge.Child = new TextBlock
                {
                    Text = model.SizeDescription(),
                    FontSize = 10,
                    Foreground = new SolidColorBrush(Color.FromRgb(0xA0, 0xA0, 0xB8))
                };
                nameRow.Children.Add(sizeBadge);
            }

            infoPanel.Children.Add(nameRow);
            infoPanel.Children.Add(new TextBlock
            {
                Text = model.Description(),
                FontSize = 12,
                Foreground = new SolidColorBrush(Color.FromRgb(0xA0, 0xA0, 0xB8)),
                Margin = new Thickness(0, 3, 0, 0)
            });

            // Download progress
            if (isDownloading)
            {
                var progressBar = new ProgressBar
                {
                    Value = _downloadManager.DownloadProgress * 100,
                    Maximum = 100,
                    Height = 4,
                    Margin = new Thickness(0, 6, 0, 0),
                    Style = (Style)FindResource("GradientProgressBar")
                };
                infoPanel.Children.Add(progressBar);
                infoPanel.Children.Add(new TextBlock
                {
                    Text = $"{(int)(_downloadManager.DownloadProgress * 100)}% downloading...",
                    FontSize = 10,
                    Foreground = new SolidColorBrush(Color.FromRgb(0x3B, 0x82, 0xF6)),
                    Margin = new Thickness(0, 4, 0, 0)
                });
            }

            Grid.SetColumn(infoPanel, 1);
            row.Children.Add(infoPanel);

            // Action button
            if (isDownloaded)
            {
                var emoji = new TextBlock
                {
                    Text = model switch
                    {
                        WhisperModel.Fast => "\u26A1",
                        WhisperModel.Accurate => "\uD83C\uDFAF",
                        WhisperModel.Precise => "\uD83D\uDD2C",
                        WhisperModel.Ultimate => "\uD83D\uDE80",
                        _ => ""
                    },
                    FontSize = 20,
                    VerticalAlignment = VerticalAlignment.Center,
                    Cursor = System.Windows.Input.Cursors.Hand
                };
                Grid.SetColumn(emoji, 2);
                row.Children.Add(emoji);
            }
            else if (isDownloading)
            {
                var spinner = new TextBlock
                {
                    Text = "\uE117",
                    FontFamily = new FontFamily("Segoe MDL2 Assets"),
                    FontSize = 16,
                    Foreground = new SolidColorBrush(Color.FromRgb(0x3B, 0x82, 0xF6)),
                    VerticalAlignment = VerticalAlignment.Center
                };
                Grid.SetColumn(spinner, 2);
                row.Children.Add(spinner);
            }
            else
            {
                var downloadBtn = new Button { Cursor = System.Windows.Input.Cursors.Hand };
                var m = model; // capture for lambda
                downloadBtn.Click += async (_, _) =>
                {
                    await _downloadManager.DownloadModel(m);
                    Dispatcher.Invoke(BuildModelOptions);
                };

                downloadBtn.Template = CreateDownloadButtonTemplate();
                Grid.SetColumn(downloadBtn, 2);
                row.Children.Add(downloadBtn);
            }

            // Wrap in a border for hover/selection state
            var rowBorder = new Border
            {
                CornerRadius = new CornerRadius(10),
                Padding = new Thickness(12),
                Background = isSelected && isDownloaded
                    ? new SolidColorBrush(Color.FromArgb(0x1A, 0x8B, 0x5C, 0xF6))
                    : Brushes.Transparent,
                BorderBrush = isSelected && isDownloaded
                    ? new SolidColorBrush(Color.FromArgb(0x4D, 0x8B, 0x5C, 0xF6))
                    : Brushes.Transparent,
                BorderThickness = new Thickness(1),
                Cursor = isDownloaded ? System.Windows.Input.Cursors.Hand : System.Windows.Input.Cursors.Arrow
            };

            if (isDownloaded)
            {
                var capturedModel = model;
                rowBorder.MouseLeftButtonDown += (_, _) =>
                {
                    _settings.SelectedModel = capturedModel;
                    BuildModelOptions();
                };
            }

            rowBorder.Child = row;
            ModelOptionsPanel.Children.Add(rowBorder);
        }
    }

    private ControlTemplate CreateDownloadButtonTemplate()
    {
        var template = new ControlTemplate(typeof(Button));

        var factory = new FrameworkElementFactory(typeof(Border));
        factory.SetValue(Border.BackgroundProperty, new SolidColorBrush(Color.FromRgb(0x3B, 0x82, 0xF6)));
        factory.SetValue(Border.CornerRadiusProperty, new CornerRadius(8));
        factory.SetValue(Border.PaddingProperty, new Thickness(10, 6, 10, 6));

        var stackFactory = new FrameworkElementFactory(typeof(StackPanel));
        stackFactory.SetValue(StackPanel.OrientationProperty, Orientation.Horizontal);

        var iconFactory = new FrameworkElementFactory(typeof(TextBlock));
        iconFactory.SetValue(TextBlock.TextProperty, "\uE896");
        iconFactory.SetValue(TextBlock.FontFamilyProperty, new FontFamily("Segoe MDL2 Assets"));
        iconFactory.SetValue(TextBlock.FontSizeProperty, 12.0);
        iconFactory.SetValue(TextBlock.ForegroundProperty, Brushes.White);
        iconFactory.SetValue(FrameworkElement.MarginProperty, new Thickness(0, 0, 4, 0));
        iconFactory.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center);
        stackFactory.AppendChild(iconFactory);

        var textFactory = new FrameworkElementFactory(typeof(TextBlock));
        textFactory.SetValue(TextBlock.TextProperty, "Download");
        textFactory.SetValue(TextBlock.FontSizeProperty, 12.0);
        textFactory.SetValue(TextBlock.FontWeightProperty, FontWeights.Medium);
        textFactory.SetValue(TextBlock.ForegroundProperty, Brushes.White);
        textFactory.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center);
        stackFactory.AppendChild(textFactory);

        factory.AppendChild(stackFactory);
        template.VisualTree = factory;
        return template;
    }

    private void PopulateAudioDevices()
    {
        InputDeviceCombo.Items.Clear();

        InputDeviceCombo.Items.Add(new ComboBoxItem
        {
            Content = "System Default",
            Tag = "system_default"
        });

        // Try to enumerate audio devices
        try
        {
            var enumerator = new NAudio.CoreAudioApi.MMDeviceEnumerator();
            var devices = enumerator.EnumerateAudioEndPoints(
                NAudio.CoreAudioApi.DataFlow.Capture,
                NAudio.CoreAudioApi.DeviceState.Active);

            foreach (var device in devices)
            {
                InputDeviceCombo.Items.Add(new ComboBoxItem
                {
                    Content = device.FriendlyName,
                    Tag = device.ID
                });
            }
        }
        catch (Exception ex)
        {
            Log.Error("Failed to enumerate audio devices", ex);
        }

        // Select current device
        var currentId = _settings.SelectedInputDeviceId;
        for (int i = 0; i < InputDeviceCombo.Items.Count; i++)
        {
            if (InputDeviceCombo.Items[i] is ComboBoxItem item && (string)item.Tag == currentId)
            {
                InputDeviceCombo.SelectedIndex = i;
                return;
            }
        }
        InputDeviceCombo.SelectedIndex = 0;
    }

    // --- Event Handlers ---

    private void DelaySlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!_isInitialized) return;
        var ms = (int)e.NewValue;
        DelayValueText.Text = $"{ms} ms";
        _settings.ActivationDelay = ms / 1000.0;
    }

    private void MultiplierSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!_isInitialized) return;
        MultiplierValueText.Text = $"{e.NewValue:F0}";
        _settings.WaveMultiplier = e.NewValue;
    }

    private void ExponentSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!_isInitialized) return;
        ExponentValueText.Text = $"{e.NewValue:F2}";
        _settings.WaveExponent = e.NewValue;
    }

    private void DivisorSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!_isInitialized) return;
        DivisorValueText.Text = $"{e.NewValue:F2}";
        _settings.WaveDivisor = e.NewValue;
    }

    private void LaunchAtLogin_Changed(object sender, RoutedEventArgs e)
    {
        if (!_isInitialized) return;
        _settings.LaunchAtLogin = LaunchAtLoginToggle.IsChecked ?? false;
    }

    private void PauseMedia_Changed(object sender, RoutedEventArgs e)
    {
        if (!_isInitialized) return;
        _settings.PauseMediaDuringRecording = PauseMediaToggle.IsChecked ?? false;
    }

    private void InputDeviceCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_isInitialized) return;
        if (InputDeviceCombo.SelectedItem is ComboBoxItem item)
        {
            _settings.SelectedInputDeviceId = (string)item.Tag;
        }
    }
}
