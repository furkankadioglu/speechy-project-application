using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using Speechy.Services;

namespace Speechy.Views.Tabs;

/// <summary>
/// Other Settings tab — app language selector.
/// Mirrors macOS OtherSettingsTab. Rows are built fully in code-behind
/// (no XAML converters required), following AdvancedTab's pattern.
/// </summary>
public partial class OtherSettingsTab : UserControl
{
    private readonly SettingsManager _settings;
    private readonly LocalizationManager _l10n;

    public OtherSettingsTab()
    {
        InitializeComponent();
        _settings = SettingsManager.Instance;
        _l10n = LocalizationManager.Instance;

        _settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(SettingsManager.AppLanguage))
                Dispatcher.Invoke(BuildLanguageRows);
        };

        Loaded += (_, _) => BuildLanguageRows();
    }

    private void BuildLanguageRows()
    {
        LanguageListPanel.Children.Clear();

        var languages = _l10n.SupportedLanguages;
        for (int i = 0; i < languages.Length; i++)
        {
            var lang = languages[i];
            var isSelected = _settings.AppLanguage == lang.Code;
            var isLast = i == languages.Length - 1;

            // Row content grid
            var grid = new Grid { Margin = new Thickness(0) };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(34) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Auto) });

            // Flag emoji
            var flagText = new TextBlock
            {
                Text = lang.Flag,
                FontSize = 20,
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(flagText, 0);
            grid.Children.Add(flagText);

            // Native name
            var nameText = new TextBlock
            {
                Text = lang.NativeName,
                FontSize = 13,
                FontWeight = FontWeights.Medium,
                Foreground = Brushes.White,
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(nameText, 1);
            grid.Children.Add(nameText);

            // Checkmark (visible only when selected)
            if (isSelected)
            {
                var checkMark = new TextBlock
                {
                    Text = "\uE73E",
                    FontFamily = new FontFamily("Segoe MDL2 Assets"),
                    FontSize = 14,
                    Foreground = new SolidColorBrush(Color.FromRgb(0x3B, 0x82, 0xF6)),
                    VerticalAlignment = VerticalAlignment.Center
                };
                Grid.SetColumn(checkMark, 2);
                grid.Children.Add(checkMark);
            }

            // Clickable row border
            var code = lang.Code; // capture for lambda
            var rowBorder = new Border
            {
                Padding = new Thickness(14, 10, 14, 10),
                Background = isSelected
                    ? new SolidColorBrush(Color.FromArgb(0x14, 0x3B, 0x82, 0xF6))
                    : Brushes.Transparent,
                Cursor = System.Windows.Input.Cursors.Hand,
                Child = grid
            };
            rowBorder.MouseLeftButtonUp += (_, _) =>
            {
                _settings.AppLanguage = code;
            };

            LanguageListPanel.Children.Add(rowBorder);

            // Divider (not after last item)
            if (!isLast)
            {
                LanguageListPanel.Children.Add(new Rectangle
                {
                    Height = 1,
                    Fill = new SolidColorBrush(Color.FromArgb(0x0D, 0xFF, 0xFF, 0xFF)),
                    Margin = new Thickness(14, 0, 14, 0)
                });
            }
        }
    }
}
