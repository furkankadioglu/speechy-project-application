using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Speechy.Models;

namespace Speechy.Views.Controls;

/// <summary>
/// Reusable slot configuration card matching macOS SlotConfigView.
/// Shows enable toggle, modifier key buttons, language dropdown,
/// with accent color theming per slot.
/// </summary>
public partial class SlotConfigControl : UserControl
{
    private HotkeyConfig _config = new();
    private Color _accentColor = Color.FromRgb(0x3B, 0x82, 0xF6);
    private bool _isUpdating;

    /// <summary>
    /// Fired when the hotkey configuration changes.
    /// </summary>
    public event Action<HotkeyConfig>? ConfigChanged;

    public SlotConfigControl()
    {
        InitializeComponent();

        // Populate language combo
        foreach (var lang in SupportedLanguages.All)
        {
            LanguageCombo.Items.Add(new ComboBoxItem
            {
                Content = $"{lang.Flag} {lang.Name}",
                Tag = lang.Code
            });
        }
    }

    /// <summary>
    /// Sets the display title (e.g., "Hotkey 1", "Toggle 1").
    /// </summary>
    public string Title
    {
        set => TitleText.Text = value;
    }

    /// <summary>
    /// Sets the accent color for this slot.
    /// </summary>
    public Color AccentColor
    {
        get => _accentColor;
        set
        {
            _accentColor = value;
            UpdateVisuals();
        }
    }

    /// <summary>
    /// Gets or sets the hotkey configuration for this slot.
    /// </summary>
    public HotkeyConfig Config
    {
        get => _config;
        set
        {
            _config = value;
            _isUpdating = true;
            EnableToggle.IsChecked = _config.IsEnabled;
            SelectLanguage(_config.Language);
            _isUpdating = false;
            UpdateVisuals();
        }
    }

    private void SelectLanguage(string code)
    {
        for (int i = 0; i < LanguageCombo.Items.Count; i++)
        {
            if (LanguageCombo.Items[i] is ComboBoxItem item && (string)item.Tag == code)
            {
                LanguageCombo.SelectedIndex = i;
                break;
            }
        }
    }

    private void UpdateVisuals()
    {
        var accentBrush = new SolidColorBrush(_accentColor);
        var accentBgBrush = new SolidColorBrush(Color.FromArgb(
            (byte)(_config.IsEnabled ? 0x33 : 0x1A),
            _accentColor.R, _accentColor.G, _accentColor.B));
        var disabledOpacity = _config.IsEnabled ? 1.0 : 0.4;

        // Status dot
        StatusDot.Fill = _config.IsEnabled ? accentBrush :
            new SolidColorBrush(Color.FromArgb(0x4D, 0xA0, 0xA0, 0xB8));

        // Title text color
        TitleText.Foreground = _config.IsEnabled
            ? Brushes.White
            : new SolidColorBrush(Color.FromRgb(0xA0, 0xA0, 0xB8));

        // Card border
        CardBorder.BorderBrush = new SolidColorBrush(Color.FromArgb(
            (byte)(_config.IsEnabled ? 0x33 : 0x1A),
            _accentColor.R, _accentColor.G, _accentColor.B));

        CardBorder.Background = new SolidColorBrush(Color.FromArgb(
            (byte)(_config.IsEnabled ? 0xFF : 0x99),
            0x2D, 0x2D, 0x42));

        // Shortcut badge
        ShortcutBadge.Background = accentBgBrush;
        ShortcutBadge.Opacity = _config.IsEnabled ? 1.0 : 0.5;
        ShortcutText.Text = _config.DisplayName;
        FlagText.Text = SupportedLanguages.GetFlag(_config.Language);

        // Mode badge
        bool isPush = _config.Mode == HotkeyMode.PushToTalk;
        ModeText.Text = isPush ? "Hold" : "Toggle";
        ModeText.Foreground = isPush
            ? new SolidColorBrush(Color.FromRgb(0x3B, 0x82, 0xF6))
            : new SolidColorBrush(Color.FromRgb(0xF9, 0x73, 0x16));
        ModeBadge.Background = new SolidColorBrush(isPush
            ? Color.FromArgb(0x26, 0x3B, 0x82, 0xF6)
            : Color.FromArgb(0x26, 0xF9, 0x73, 0x16));

        // Modifier buttons
        ModifierGrid.Opacity = disabledOpacity;
        ModifierGrid.IsEnabled = _config.IsEnabled;
        LanguageCombo.IsEnabled = _config.IsEnabled;

        UpdateModifierButton(ShiftButton, _config.Modifiers.HasFlag(ModifierKeys.Shift));
        UpdateModifierButton(CtrlButton, _config.Modifiers.HasFlag(ModifierKeys.Ctrl));
        UpdateModifierButton(AltButton, _config.Modifiers.HasFlag(ModifierKeys.Alt));
        UpdateModifierButton(WinButton, _config.Modifiers.HasFlag(ModifierKeys.Win));
    }

    private void UpdateModifierButton(Button button, bool isOn)
    {
        button.ApplyTemplate();
        if (VisualTreeHelper.GetChildrenCount(button) > 0)
        {
            var border = VisualTreeHelper.GetChild(button, 0) as Border;
            if (border != null)
            {
                if (isOn)
                {
                    border.Background = new SolidColorBrush(_accentColor);
                    border.BorderBrush = new SolidColorBrush(_accentColor);
                }
                else
                {
                    border.Background = new SolidColorBrush(Color.FromRgb(0x25, 0x25, 0x38));
                    border.BorderBrush = new SolidColorBrush(Color.FromArgb(0x1A, 0xFF, 0xFF, 0xFF));
                }

                // Update text color
                if (VisualTreeHelper.GetChildrenCount(border) > 0 &&
                    VisualTreeHelper.GetChild(border, 0) is TextBlock tb)
                {
                    tb.Foreground = isOn ? Brushes.White :
                        new SolidColorBrush(Color.FromRgb(0xE0, 0xE0, 0xE0));
                }
            }
        }
    }

    private void ToggleModifier(ModifierKeys flag)
    {
        if (_config.Modifiers.HasFlag(flag))
            _config.Modifiers &= ~flag;
        else
            _config.Modifiers |= flag;
        UpdateVisuals();
        ConfigChanged?.Invoke(_config);
    }

    private void ShiftButton_Click(object sender, RoutedEventArgs e) => ToggleModifier(ModifierKeys.Shift);
    private void CtrlButton_Click(object sender, RoutedEventArgs e) => ToggleModifier(ModifierKeys.Ctrl);
    private void AltButton_Click(object sender, RoutedEventArgs e) => ToggleModifier(ModifierKeys.Alt);
    private void WinButton_Click(object sender, RoutedEventArgs e) => ToggleModifier(ModifierKeys.Win);

    private void EnableToggle_Changed(object sender, RoutedEventArgs e)
    {
        if (_isUpdating) return;
        _config.IsEnabled = EnableToggle.IsChecked ?? false;
        UpdateVisuals();
        ConfigChanged?.Invoke(_config);
    }

    private void LanguageCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isUpdating) return;
        if (LanguageCombo.SelectedItem is ComboBoxItem item)
        {
            _config.Language = (string)item.Tag;
            UpdateVisuals();
            ConfigChanged?.Invoke(_config);
        }
    }
}
