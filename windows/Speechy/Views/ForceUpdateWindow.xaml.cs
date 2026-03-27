using System.Diagnostics;
using System.Windows;

namespace Speechy.Views;

/// <summary>
/// Force update window shown when the current app version is below the minimum
/// supported version returned by the version API. Mirrors macOS ForceUpdateView.
///
/// The window stays on top and cannot be closed — the user must download the update.
/// </summary>
public partial class ForceUpdateWindow : Window
{
    private readonly string _updateUrl;

    /// <summary>
    /// Initializes the ForceUpdateWindow with version information.
    /// </summary>
    /// <param name="currentVersion">The version currently installed (e.g. "1.0.0").</param>
    /// <param name="minimumVersion">The minimum version required by the server.</param>
    /// <param name="latestVersion">The latest available version.</param>
    /// <param name="updateUrl">The URL to open when the user clicks Download Update.</param>
    public ForceUpdateWindow(
        string currentVersion,
        string minimumVersion,
        string latestVersion,
        string updateUrl)
    {
        InitializeComponent();

        _updateUrl = updateUrl;

        CurrentVersionText.Text = currentVersion;
        LatestVersionText.Text = latestVersion;

        SubtitleText.Text =
            $"Version {currentVersion} is no longer supported. " +
            $"Please update to version {minimumVersion} or later.";
    }

    private void DownloadButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo(_updateUrl)
            {
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            Services.Log.Error("ForceUpdateWindow: failed to open update URL", ex);
        }
    }
}
