using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Speechy.Models;
using Speechy.Services;

namespace Speechy.Views.Tabs;

/// <summary>
/// Prompt tab: Saved Words + Modal Configurations.
/// Mirrors macOS PromptTab.
/// </summary>
public partial class PromptTab : UserControl
{
    private readonly SettingsManager _settings;

    public PromptTab()
    {
        InitializeComponent();
        _settings = SettingsManager.Instance;
        _settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(SettingsManager.SavedWords) or nameof(SettingsManager.ModalConfig))
                Dispatcher.Invoke(Refresh);
        };
        Loaded += (_, _) => BuildModalOptions();
        Loaded += (_, _) => Refresh();
    }

    // ─── Refresh (word list + prompt preview) ─────────────────────────────

    private void Refresh()
    {
        RefreshWordList();
        RefreshPromptPreview();
    }

    private void RefreshWordList()
    {
        var words = _settings.SavedWords;
        WordCountText.Text = $"{words.Count} word{(words.Count != 1 ? "s" : "")}";

        if (words.Count == 0)
        {
            EmptyWordsPanel.Visibility = Visibility.Visible;
            WordListContainer.Visibility = Visibility.Visible;
            WordListBorder.Visibility = Visibility.Collapsed;
        }
        else
        {
            EmptyWordsPanel.Visibility = Visibility.Collapsed;
            WordListContainer.Visibility = Visibility.Collapsed;
            WordListBorder.Visibility = Visibility.Visible;
            WordsItemsControl.ItemsSource = null;
            WordsItemsControl.ItemsSource = new List<string>(words);
        }
    }

    private void RefreshPromptPreview()
    {
        var prompt = _settings.WhisperPrompt;
        if (string.IsNullOrEmpty(prompt))
        {
            PromptPreviewBorder.Visibility = Visibility.Collapsed;
        }
        else
        {
            PromptPreviewText.Text = $"Prompt: \"{prompt}\"";
            PromptPreviewBorder.Visibility = Visibility.Visible;
        }
        // Re-highlight selected modal option
        RefreshModalSelection();
    }

    // ─── Word management ──────────────────────────────────────────────────

    private void AddWordButton_Click(object sender, RoutedEventArgs e) => AddWord();

    private void NewWordInput_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Return || e.Key == Key.Enter) AddWord();
    }

    private void AddWord()
    {
        var word = NewWordInput.Text.Trim();
        if (string.IsNullOrEmpty(word)) return;
        if (_settings.SavedWords.Contains(word)) { NewWordInput.Text = ""; return; }

        var updated = new List<string>(_settings.SavedWords) { word };
        _settings.SavedWords = updated;
        NewWordInput.Text = "";
    }

    private void RemoveWord_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string word)
        {
            var updated = new List<string>(_settings.SavedWords);
            updated.Remove(word);
            _settings.SavedWords = updated;
        }
    }

    // ─── Modal config options ─────────────────────────────────────────────

    private void BuildModalOptions()
    {
        ModalConfigPanel.Children.Clear();
        var configs = ModalConfigExtensions.AllCases().ToList();

        for (int i = 0; i < configs.Count; i++)
        {
            var config = configs[i];
            var isLast = i == configs.Count - 1;

            var row = BuildConfigRow(config);
            ModalConfigPanel.Children.Add(row);

            if (!isLast)
            {
                ModalConfigPanel.Children.Add(new Rectangle
                {
                    Height = 1,
                    Fill = new SolidColorBrush(Color.FromArgb(0x0D, 0xFF, 0xFF, 0xFF)),
                    Margin = new Thickness(48, 0, 12, 0)
                });
            }
        }
    }

    private Border BuildConfigRow(ModalConfig config)
    {
        var isSelected = _settings.ModalConfig == config;

        var border = new Border
        {
            Background = isSelected
                ? new SolidColorBrush(Color.FromArgb(0x20, 0xAF, 0x52, 0xDE))
                : Brushes.Transparent,
            Padding = new Thickness(14, 10, 14, 10),
            Tag = config,
            Cursor = Cursors.Hand
        };

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(6) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(22) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        // Radio circle
        var radioOuter = new Ellipse
        {
            Width = 18, Height = 18,
            Stroke = isSelected
                ? new SolidColorBrush(Color.FromRgb(0xAF, 0x52, 0xDE))
                : new SolidColorBrush(Color.FromArgb(0x66, 0xFF, 0xFF, 0xFF)),
            StrokeThickness = 2
        };
        Grid.SetColumn(radioOuter, 0);

        if (isSelected)
        {
            var radioInner = new Ellipse
            {
                Width = 10, Height = 10,
                Fill = new SolidColorBrush(Color.FromRgb(0xAF, 0x52, 0xDE)),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };
            var radioGrid = new Grid { Width = 18, Height = 18 };
            radioGrid.Children.Add(radioOuter);
            radioGrid.Children.Add(radioInner);
            Grid.SetColumn(radioGrid, 0);
            grid.Children.Add(radioGrid);
        }
        else
        {
            grid.Children.Add(radioOuter);
        }

        // Icon
        var iconText = new TextBlock
        {
            Text = config.Icon(),
            FontFamily = new FontFamily("Segoe MDL2 Assets"),
            FontSize = 13,
            Foreground = isSelected
                ? new SolidColorBrush(Color.FromRgb(0xAF, 0x52, 0xDE))
                : new SolidColorBrush(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF)),
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center
        };
        Grid.SetColumn(iconText, 2);
        grid.Children.Add(iconText);

        // Name + description
        var textStack = new StackPanel { Margin = new Thickness(10, 0, 0, 0) };
        textStack.Children.Add(new TextBlock
        {
            Text = config.DisplayName(),
            FontSize = 13,
            FontWeight = isSelected ? FontWeights.SemiBold : FontWeights.Medium,
            Foreground = Brushes.White
        });
        textStack.Children.Add(new TextBlock
        {
            Text = config.Description(),
            FontSize = 11,
            Foreground = new SolidColorBrush(Color.FromRgb(0x6B, 0x72, 0x80))
        });
        Grid.SetColumn(textStack, 4);
        grid.Children.Add(textStack);

        border.Child = grid;
        border.MouseLeftButtonUp += (_, _) =>
        {
            _settings.ModalConfig = config;
            RefreshModalSelection();
        };

        return border;
    }

    private void RefreshModalSelection()
    {
        // Rebuild to reflect new selection (simpler than patching individual children)
        BuildModalOptions();
    }
}
