using System.Windows;
using System.Windows.Media;
using System.Windows.Shapes;
using Speechy.Services;

namespace Speechy.Views;

/// <summary>
/// 3-page onboarding window matching macOS OnboardingView.
/// Page 0: Welcome with features, Page 1: Permissions info, Page 2: How to use.
/// Includes page dot indicators and Next/Back/Get Started navigation.
/// </summary>
public partial class OnboardingWindow : Window
{
    private int _currentPage;
    private readonly StackPanel[] _pages;
    private readonly Ellipse[] _dots;

    public OnboardingWindow()
    {
        InitializeComponent();
        _pages = new[] { Page0, Page1, Page2 };
        _dots = new[] { Dot0, Dot1, Dot2 };
        UpdatePage();
    }

    private void BackButton_Click(object sender, RoutedEventArgs e)
    {
        if (_currentPage > 0)
        {
            _currentPage--;
            UpdatePage();
        }
    }

    private void NextButton_Click(object sender, RoutedEventArgs e)
    {
        if (_currentPage < 2)
        {
            _currentPage++;
            UpdatePage();
        }
        else
        {
            // Get Started clicked
            SettingsManager.Instance.HasCompletedOnboarding = true;
            DialogResult = true;
            Close();
        }
    }

    private void UpdatePage()
    {
        // Show/hide pages
        for (int i = 0; i < _pages.Length; i++)
        {
            _pages[i].Visibility = i == _currentPage ? Visibility.Visible : Visibility.Collapsed;
        }

        // Update dots
        var activeBrush = new SolidColorBrush(Color.FromRgb(0x3B, 0x82, 0xF6));
        var inactiveBrush = new SolidColorBrush(Color.FromArgb(0x4D, 0x80, 0x80, 0x80));
        for (int i = 0; i < _dots.Length; i++)
        {
            _dots[i].Fill = i == _currentPage ? activeBrush : inactiveBrush;
        }

        // Back button
        BackButton.Visibility = _currentPage > 0 ? Visibility.Visible : Visibility.Collapsed;

        // Next/Get Started button
        NextButton.Content = _currentPage < 2 ? "Next" : "Get Started";
    }
}
