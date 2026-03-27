using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Speechy.Views;

/// <summary>
/// Main settings window matching macOS SettingsView with sidebar navigation.
/// Left sidebar (168px) with logo, nav items, quit button.
/// Right content area switches between Settings, Advanced, History, and License tabs.
/// Window: 672x816.
/// </summary>
public partial class SettingsWindow : Window
{
    private int _selectedTab;
    private readonly Button[] _navButtons;
    private readonly UIElement[] _tabContents;

    /// <summary>
    /// Fired when the user clicks Quit in the sidebar.
    /// </summary>
    public event Action? OnQuitRequested;

    public SettingsWindow()
    {
        InitializeComponent();
        _navButtons = new[] { NavSettings, NavAdvanced, NavHistory, NavLicense, NavPrompt };
        _tabContents = new UIElement[] { SettingsTabContent, AdvancedTabContent, HistoryTabContent, LicenseTabContent, PromptTabContent };
        SelectTab(0);
    }

    private void NavSettings_Click(object sender, RoutedEventArgs e) => SelectTab(0);
    private void NavAdvanced_Click(object sender, RoutedEventArgs e) => SelectTab(1);
    private void NavHistory_Click(object sender, RoutedEventArgs e) => SelectTab(2);
    private void NavLicense_Click(object sender, RoutedEventArgs e) => SelectTab(3);
    private void NavPrompt_Click(object sender, RoutedEventArgs e) => SelectTab(4);

    private void QuitButton_Click(object sender, RoutedEventArgs e)
    {
        OnQuitRequested?.Invoke();
    }

    private void SelectTab(int index)
    {
        _selectedTab = index;

        // Update content visibility
        for (int i = 0; i < _tabContents.Length; i++)
        {
            _tabContents[i].Visibility = i == index ? Visibility.Visible : Visibility.Collapsed;
        }

        // Update nav button styles
        var selectedGradient = new LinearGradientBrush(
            Color.FromRgb(0x3B, 0x82, 0xF6),
            Color.FromArgb(0xCC, 0x3B, 0x82, 0xF6),
            0);

        var transparentBrush = Brushes.Transparent;
        var whiteBrush = Brushes.White;
        var secondaryBrush = new SolidColorBrush(Color.FromRgb(0xA0, 0xA0, 0xB8));

        for (int i = 0; i < _navButtons.Length; i++)
        {
            // Access the border inside the button template
            var button = _navButtons[i];
            button.ApplyTemplate();

            // We need to find the Border named "navBorder" in the template
            var border = FindNavBorder(button);
            if (border != null)
            {
                border.Background = i == index ? selectedGradient : transparentBrush;
            }

            // Update text colors
            var stack = FindNavStackPanel(button);
            if (stack != null)
            {
                foreach (var child in stack.Children)
                {
                    if (child is TextBlock tb)
                    {
                        tb.Foreground = i == index ? whiteBrush : secondaryBrush;
                    }
                }
            }
        }
    }

    private static Border? FindNavBorder(Button button)
    {
        if (VisualTreeHelper.GetChildrenCount(button) > 0)
        {
            var child = VisualTreeHelper.GetChild(button, 0);
            if (child is Border border)
                return border;
        }
        return null;
    }

    private static StackPanel? FindNavStackPanel(Button button)
    {
        var border = FindNavBorder(button);
        if (border != null && VisualTreeHelper.GetChildrenCount(border) > 0)
        {
            var child = VisualTreeHelper.GetChild(border, 0);
            if (child is StackPanel sp)
                return sp;
        }
        return null;
    }
}
