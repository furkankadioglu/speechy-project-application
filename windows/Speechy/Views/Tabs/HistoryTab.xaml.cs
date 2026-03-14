using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using Speechy.Models;
using Speechy.Services;

namespace Speechy.Views.Tabs;

/// <summary>
/// History tab matching macOS HistoryTab.
/// Shows transcription history with flag, text preview, relative time,
/// copy and delete buttons per entry. Clear All at bottom.
/// Empty state when no history.
/// </summary>
public partial class HistoryTab : UserControl
{
    private readonly SettingsManager _settings;

    public HistoryTab()
    {
        InitializeComponent();
        _settings = SettingsManager.Instance;
        Loaded += (_, _) => RefreshHistory();

        // Listen for history changes
        _settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(SettingsManager.History))
            {
                Dispatcher.Invoke(RefreshHistory);
            }
        };
    }

    private void RefreshHistory()
    {
        HistoryList.Children.Clear();
        var history = _settings.History;

        if (history.Count == 0)
        {
            EmptyState.Visibility = Visibility.Visible;
            HistoryScrollViewer.Visibility = Visibility.Collapsed;
            FooterPanel.Visibility = Visibility.Collapsed;
            return;
        }

        EmptyState.Visibility = Visibility.Collapsed;
        HistoryScrollViewer.Visibility = Visibility.Visible;
        FooterPanel.Visibility = Visibility.Visible;
        ItemCountText.Text = $"{history.Count} items";

        foreach (var entry in history)
        {
            HistoryList.Children.Add(CreateHistoryRow(entry));
        }
    }

    private Border CreateHistoryRow(TranscriptionEntry entry)
    {
        var card = new Border
        {
            Background = new SolidColorBrush(Color.FromRgb(0x2D, 0x2D, 0x42)),
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(12),
            Margin = new Thickness(0, 0, 0, 8),
            BorderThickness = new Thickness(1),
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x0D, 0xFF, 0xFF, 0xFF)),
            Effect = new DropShadowEffect
            {
                Color = Colors.Black,
                BlurRadius = 2,
                ShadowDepth = 1,
                Opacity = 0.05,
                Direction = 270
            }
        };

        var stack = new StackPanel();

        // Header: flag + time + action buttons
        var header = new Grid();
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        // Flag
        var flag = new TextBlock
        {
            Text = entry.Flag,
            FontSize = 18,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 8, 0)
        };
        Grid.SetColumn(flag, 0);
        header.Children.Add(flag);

        // Relative time
        var timeText = new TextBlock
        {
            Text = GetRelativeTime(entry.CreatedAt),
            FontSize = 12,
            Foreground = new SolidColorBrush(Color.FromRgb(0xA0, 0xA0, 0xB8)),
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(timeText, 1);
        header.Children.Add(timeText);

        // Action buttons
        var actionPanel = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Opacity = 0.6
        };

        // Copy button
        var copyBtn = CreateIconButton("\uE8C8", "Copy");
        var entryText = entry.Text;
        copyBtn.Click += (_, _) =>
        {
            Clipboard.SetText(entryText);
            // Visual feedback: change icon briefly
            if (copyBtn.Content is TextBlock tb)
            {
                tb.Text = "\uE73E"; // checkmark
                tb.Foreground = new SolidColorBrush(Color.FromRgb(0x22, 0xC5, 0x5E));
                var timer = new System.Windows.Threading.DispatcherTimer
                {
                    Interval = TimeSpan.FromMilliseconds(1500)
                };
                timer.Tick += (_, _) =>
                {
                    tb.Text = "\uE8C8";
                    tb.Foreground = new SolidColorBrush(Color.FromRgb(0xA0, 0xA0, 0xB8));
                    timer.Stop();
                };
                timer.Start();
            }
        };
        actionPanel.Children.Add(copyBtn);

        // Delete button
        var deleteBtn = CreateIconButton("\uE711", "Delete");
        deleteBtn.Click += (_, _) =>
        {
            _settings.History.Remove(entry);
            _settings.Save();
            RefreshHistory();
        };
        actionPanel.Children.Add(deleteBtn);

        Grid.SetColumn(actionPanel, 3);
        header.Children.Add(actionPanel);

        stack.Children.Add(header);

        // Text content
        var textContent = new TextBlock
        {
            Text = entry.Text,
            FontSize = 14,
            Foreground = Brushes.White,
            TextWrapping = TextWrapping.Wrap,
            MaxHeight = 60, // ~3 lines
            TextTrimming = TextTrimming.CharacterEllipsis,
            Margin = new Thickness(0, 8, 0, 0)
        };
        stack.Children.Add(textContent);

        card.Child = stack;

        // Hover effect
        card.MouseEnter += (_, _) =>
        {
            card.BorderBrush = new SolidColorBrush(Color.FromArgb(0x1A, 0xFF, 0xFF, 0xFF));
            actionPanel.Opacity = 1.0;
        };
        card.MouseLeave += (_, _) =>
        {
            card.BorderBrush = new SolidColorBrush(Color.FromArgb(0x0D, 0xFF, 0xFF, 0xFF));
            actionPanel.Opacity = 0.6;
        };

        return card;
    }

    private Button CreateIconButton(string icon, string tooltip)
    {
        var btn = new Button
        {
            Width = 28, Height = 28,
            Cursor = Cursors.Hand,
            ToolTip = tooltip,
            Margin = new Thickness(2, 0, 0, 0)
        };

        var template = new ControlTemplate(typeof(Button));
        var borderFactory = new FrameworkElementFactory(typeof(Border));
        borderFactory.SetValue(Border.BackgroundProperty,
            new SolidColorBrush(Color.FromRgb(0x2D, 0x2D, 0x42)));
        borderFactory.SetValue(Border.CornerRadiusProperty, new CornerRadius(6));
        borderFactory.Name = "iconBorder";

        var contentFactory = new FrameworkElementFactory(typeof(ContentPresenter));
        contentFactory.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
        contentFactory.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
        borderFactory.AppendChild(contentFactory);

        template.VisualTree = borderFactory;

        var hoverTrigger = new Trigger { Property = UIElement.IsMouseOverProperty, Value = true };
        hoverTrigger.Setters.Add(new Setter(Border.BackgroundProperty,
            new SolidColorBrush(Color.FromRgb(0x35, 0x35, 0x50)), "iconBorder"));
        template.Triggers.Add(hoverTrigger);

        btn.Template = template;
        btn.Content = new TextBlock
        {
            Text = icon,
            FontFamily = new FontFamily("Segoe MDL2 Assets"),
            FontSize = 12,
            Foreground = new SolidColorBrush(Color.FromRgb(0xA0, 0xA0, 0xB8)),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };

        return btn;
    }

    private static string GetRelativeTime(DateTime dateTime)
    {
        var utcNow = DateTime.UtcNow;
        var span = utcNow - dateTime;

        if (span.TotalSeconds < 60) return "just now";
        if (span.TotalMinutes < 60) return $"{(int)span.TotalMinutes} min ago";
        if (span.TotalHours < 24) return $"{(int)span.TotalHours} hours ago";
        if (span.TotalDays < 7) return $"{(int)span.TotalDays} days ago";
        return dateTime.ToLocalTime().ToString("MMM d, yyyy");
    }

    private void ClearAll_Click(object sender, RoutedEventArgs e)
    {
        var result = MessageBox.Show(
            "All recordings will be deleted. This action cannot be undone.",
            "Clear History",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);

        if (result == MessageBoxResult.Yes)
        {
            _settings.ClearHistory();
            RefreshHistory();
        }
    }
}
