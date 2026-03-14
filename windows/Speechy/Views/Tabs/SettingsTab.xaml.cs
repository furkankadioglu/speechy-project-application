using System.Windows.Controls;
using System.Windows.Media;
using Speechy.Services;

namespace Speechy.Views.Tabs;

/// <summary>
/// Settings tab matching macOS SettingsTab.
/// Shows 4 hotkey slot configurations in cards with colored accents.
/// Slot 1 (blue), Slot 2 (green) = Push-to-Talk
/// Slot 3 (orange), Slot 4 (purple/red) = Toggle-to-Talk
/// </summary>
public partial class SettingsTab : UserControl
{
    private readonly SettingsManager _settings;

    public SettingsTab()
    {
        InitializeComponent();
        _settings = SettingsManager.Instance;
        Loaded += (_, _) => InitializeSlots();
    }

    private void InitializeSlots()
    {
        // Slot 1: Blue
        Slot1Config.Title = "Hotkey 1";
        Slot1Config.AccentColor = Color.FromRgb(0x3B, 0x82, 0xF6);
        Slot1Config.Config = _settings.Slot1.Clone();
        Slot1Config.ConfigChanged += config => _settings.Slot1 = config;

        // Slot 2: Green
        Slot2Config.Title = "Hotkey 2";
        Slot2Config.AccentColor = Color.FromRgb(0x22, 0xC5, 0x5E);
        Slot2Config.Config = _settings.Slot2.Clone();
        Slot2Config.ConfigChanged += config => _settings.Slot2 = config;

        // Slot 3: Orange
        Slot3Config.Title = "Toggle 1";
        Slot3Config.AccentColor = Color.FromRgb(0xF9, 0x73, 0x16);
        Slot3Config.Config = _settings.Slot3.Clone();
        Slot3Config.ConfigChanged += config => _settings.Slot3 = config;

        // Slot 4: Purple/Red
        Slot4Config.Title = "Toggle 2";
        Slot4Config.AccentColor = Color.FromRgb(0xEF, 0x44, 0x44);
        Slot4Config.Config = _settings.Slot4.Clone();
        Slot4Config.ConfigChanged += config => _settings.Slot4 = config;
    }
}
