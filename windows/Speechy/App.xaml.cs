using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Interop;
using Hardcodet.Wpf.TaskbarNotification;
using Speechy.Helpers;
using Speechy.Services;

namespace Speechy;

/// <summary>
/// Application entry point. Handles:
/// - Single instance enforcement via Mutex
/// - Splash screen -> license check -> permission check -> main app flow
/// - System tray icon with context menu
/// - Ctrl+Shift+S global hotkey for settings window
/// - Core service initialization and lifecycle
/// </summary>
public partial class App : Application
{
    private const string MutexName = "Global\\SpeechyDesktopApp_SingleInstance";
    private const int SettingsHotkeyId = 9001;

    private Mutex? _instanceMutex;
    private TaskbarIcon? _trayIcon;
    private HotkeyManager? _hotkeyManager;
    private AudioRecorder? _audioRecorder;
    private WhisperTranscriber? _whisperTranscriber;
    private MediaControlManager? _mediaControlManager;
    private HwndSource? _hwndSource;
    private Window? _settingsWindow;
    private bool _isProcessingRecording;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Single instance enforcement
        _instanceMutex = new Mutex(true, MutexName, out bool createdNew);
        if (!createdNew)
        {
            MessageBox.Show("Speechy is already running.", "Speechy",
                MessageBoxButton.OK, MessageBoxImage.Information);
            Shutdown();
            return;
        }

        Log.Info("Application starting");

        // Initialize core services
        _audioRecorder = new AudioRecorder();
        _whisperTranscriber = new WhisperTranscriber();
        _mediaControlManager = new MediaControlManager();
        _hotkeyManager = new HotkeyManager();
        _hotkeyManager.OnRecordingStart += OnRecordingStart;
        _hotkeyManager.OnRecordingStop += OnRecordingStop;

        // Setup system tray icon
        SetupTrayIcon();

        // Show splash briefly, then proceed with checks
        await ShowSplashAndInitialize();
    }

    private async Task ShowSplashAndInitialize()
    {
        // Show splash screen
        var splash = new Window
        {
            Title = "Speechy",
            Width = 400,
            Height = 300,
            WindowStartupLocation = WindowStartupLocation.CenterScreen,
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = (System.Windows.Media.Brush)FindResource("BgDarkBrush"),
            ResizeMode = ResizeMode.NoResize
        };

        var splashContent = new System.Windows.Controls.StackPanel
        {
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center
        };

        // Logo circle
        var logoGrid = new System.Windows.Controls.Grid
        {
            Width = 80,
            Height = 80,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 16)
        };

        var logoCircle = new System.Windows.Shapes.Ellipse
        {
            Fill = (System.Windows.Media.Brush)FindResource("PrimaryGradient")
        };
        logoGrid.Children.Add(logoCircle);

        var micText = new System.Windows.Controls.TextBlock
        {
            Text = "\U0001F3A4",
            FontSize = 32,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        logoGrid.Children.Add(micText);

        splashContent.Children.Add(logoGrid);

        var titleText = new System.Windows.Controls.TextBlock
        {
            Text = "Speechy",
            FontSize = 28,
            FontWeight = FontWeights.Bold,
            Foreground = (System.Windows.Media.Brush)FindResource("TextPrimaryBrush"),
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 8)
        };
        splashContent.Children.Add(titleText);

        var subtitleText = new System.Windows.Controls.TextBlock
        {
            Text = "Speech to Text",
            FontSize = 14,
            Foreground = (System.Windows.Media.Brush)FindResource("TextSecondaryBrush"),
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 24)
        };
        splashContent.Children.Add(subtitleText);

        var loadingText = new System.Windows.Controls.TextBlock
        {
            Text = "Loading...",
            FontSize = 12,
            Foreground = (System.Windows.Media.Brush)FindResource("TextMutedBrush"),
            HorizontalAlignment = HorizontalAlignment.Center
        };
        splashContent.Children.Add(loadingText);

        splash.Content = splashContent;
        splash.Show();

        // Brief splash delay
        await Task.Delay(1500);

        // License check
        var licenseManager = LicenseManager.Instance;
        if (!licenseManager.IsLicensed)
        {
            splash.Close();
            var activated = await ShowLicenseWindow();
            if (!activated)
            {
                Log.Info("License not activated, shutting down");
                Shutdown();
                return;
            }
        }
        else
        {
            // Verify license in background
            _ = licenseManager.VerifyInBackground();
        }

        splash.Close();

        // Version check — runs in background, blocks app if current version is below minimum
        await Task.Run(async () =>
        {
            await VersionManager.Instance.CheckVersionAsync((minVer, latestVer, updateUrl) =>
            {
                Dispatcher.Invoke(() =>
                {
                    var win = new Views.ForceUpdateWindow(
                        VersionManager.Instance.CurrentVersion,
                        minVer,
                        latestVer,
                        updateUrl
                    );
                    win.ShowDialog();
                });
            });
        });

        // Install keyboard hook and register global hotkey
        _hotkeyManager!.Install();
        RegisterSettingsHotkey();

        Log.Info("Application initialized and ready");
    }

    private Task<bool> ShowLicenseWindow()
    {
        var tcs = new TaskCompletionSource<bool>();

        var window = new Window
        {
            Title = "Speechy - License",
            Width = 440,
            Height = 480,
            WindowStartupLocation = WindowStartupLocation.CenterScreen,
            Background = (System.Windows.Media.Brush)FindResource("BgDarkBrush"),
            ResizeMode = ResizeMode.NoResize,
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true
        };

        var panel = new System.Windows.Controls.StackPanel
        {
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
            Width = 360
        };

        // Logo
        var logoGrid = new System.Windows.Controls.Grid
        {
            Width = 80,
            Height = 80,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 16)
        };
        var circle = new System.Windows.Shapes.Ellipse
        {
            Fill = (System.Windows.Media.Brush)FindResource("PrimaryGradient")
        };
        logoGrid.Children.Add(circle);
        var mic = new System.Windows.Controls.TextBlock
        {
            Text = "\U0001F3A4",
            FontSize = 32,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        logoGrid.Children.Add(mic);
        panel.Children.Add(logoGrid);

        var title = new System.Windows.Controls.TextBlock
        {
            Text = "Speechy",
            FontSize = 28,
            FontWeight = FontWeights.Bold,
            Foreground = (System.Windows.Media.Brush)FindResource("TextPrimaryBrush"),
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 4)
        };
        panel.Children.Add(title);

        var subtitle = new System.Windows.Controls.TextBlock
        {
            Text = "Enter your license key to get started",
            FontSize = 14,
            Foreground = (System.Windows.Media.Brush)FindResource("TextSecondaryBrush"),
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 32)
        };
        panel.Children.Add(subtitle);

        // Label
        var label = new System.Windows.Controls.TextBlock
        {
            Text = "License Key",
            FontSize = 12,
            FontWeight = FontWeights.SemiBold,
            Foreground = (System.Windows.Media.Brush)FindResource("TextSecondaryBrush"),
            Margin = new Thickness(0, 0, 0, 8)
        };
        panel.Children.Add(label);

        // Input
        var input = new System.Windows.Controls.TextBox
        {
            Style = (Style)FindResource("DarkTextBox"),
            Margin = new Thickness(0, 0, 0, 16)
        };
        panel.Children.Add(input);

        // Error text
        var errorText = new System.Windows.Controls.TextBlock
        {
            FontSize = 12,
            Foreground = (System.Windows.Media.Brush)FindResource("ErrorRedBrush"),
            Margin = new Thickness(0, 0, 0, 12),
            Visibility = Visibility.Collapsed,
            TextWrapping = TextWrapping.Wrap
        };
        panel.Children.Add(errorText);

        // Activate button
        var activateBtn = new System.Windows.Controls.Button
        {
            Content = "Activate License",
            Style = (Style)FindResource("PrimaryButton"),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            Margin = new Thickness(0, 0, 0, 24)
        };
        panel.Children.Add(activateBtn);

        // Footer
        var footer = new System.Windows.Controls.TextBlock
        {
            FontSize = 12,
            Foreground = (System.Windows.Media.Brush)FindResource("TextMutedBrush"),
            HorizontalAlignment = HorizontalAlignment.Center,
            Text = "Get a free trial at speechy.frkn.com.tr"
        };
        panel.Children.Add(footer);

        activateBtn.Click += async (_, _) =>
        {
            var key = input.Text.Trim();
            if (string.IsNullOrEmpty(key)) return;

            activateBtn.IsEnabled = false;
            activateBtn.Content = "Verifying...";
            errorText.Visibility = Visibility.Collapsed;

            var (success, message) = await LicenseManager.Instance.Activate(key);

            if (success)
            {
                window.Close();
                tcs.TrySetResult(true);
            }
            else
            {
                errorText.Text = message;
                errorText.Visibility = Visibility.Visible;
                activateBtn.IsEnabled = true;
                activateBtn.Content = "Activate License";
            }
        };

        window.Closed += (_, _) =>
        {
            tcs.TrySetResult(LicenseManager.Instance.IsLicensed);
        };

        window.Content = panel;
        window.ShowDialog();

        return tcs.Task;
    }

    private void SetupTrayIcon()
    {
        _trayIcon = new TaskbarIcon
        {
            ToolTipText = "Speechy - Speech to Text"
        };

        var contextMenu = new System.Windows.Controls.ContextMenu();

        var settingsItem = new System.Windows.Controls.MenuItem { Header = "Settings (Ctrl+Shift+S)" };
        settingsItem.Click += (_, _) => ShowSettingsWindow();
        contextMenu.Items.Add(settingsItem);

        contextMenu.Items.Add(new System.Windows.Controls.Separator());

        var quitItem = new System.Windows.Controls.MenuItem { Header = "Quit Speechy" };
        quitItem.Click += (_, _) =>
        {
            Log.Info("User requested quit");
            Shutdown();
        };
        contextMenu.Items.Add(quitItem);

        _trayIcon.ContextMenu = contextMenu;
        _trayIcon.TrayMouseDoubleClick += (_, _) => ShowSettingsWindow();
    }

    private void RegisterSettingsHotkey()
    {
        try
        {
            // Create a hidden window to receive hotkey messages
            var helper = new WindowInteropHelper(new Window());
            _hwndSource = HwndSource.FromHwnd(helper.EnsureHandle());
            _hwndSource?.AddHook(WndProc);

            // Register Ctrl+Shift+S
            var registered = NativeMethods.RegisterHotKey(
                _hwndSource!.Handle,
                SettingsHotkeyId,
                NativeMethods.MOD_CONTROL | NativeMethods.MOD_SHIFT | NativeMethods.MOD_NOREPEAT,
                0x53 // VK_S
            );

            if (registered)
            {
                Log.Info("Settings hotkey registered (Ctrl+Shift+S)");
            }
            else
            {
                Log.Error($"Failed to register settings hotkey. Error: {Marshal.GetLastWin32Error()}");
            }
        }
        catch (Exception ex)
        {
            Log.Error("Failed to register settings hotkey", ex);
        }
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == NativeMethods.WM_HOTKEY && wParam.ToInt32() == SettingsHotkeyId)
        {
            ShowSettingsWindow();
            handled = true;
        }
        return IntPtr.Zero;
    }

    private void ShowSettingsWindow()
    {
        if (_settingsWindow != null && _settingsWindow.IsVisible)
        {
            _settingsWindow.Activate();
            return;
        }

        _settingsWindow = new Window
        {
            Title = "Speechy Settings",
            Width = 560,
            Height = 680,
            WindowStartupLocation = WindowStartupLocation.CenterScreen,
            Background = (System.Windows.Media.Brush)FindResource("BgDarkBrush"),
            ResizeMode = ResizeMode.CanResize,
            MinWidth = 480,
            MinHeight = 500
        };

        // Placeholder content - settings UI will be built in Views/
        var placeholder = new System.Windows.Controls.TextBlock
        {
            Text = "Settings window - Views to be implemented",
            Foreground = (System.Windows.Media.Brush)FindResource("TextSecondaryBrush"),
            FontSize = 16,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        _settingsWindow.Content = placeholder;

        _settingsWindow.Show();
        Log.Info("Settings window opened");
    }

    private void OnRecordingStart(string language, string flag)
    {
        if (_isProcessingRecording) return;

        Dispatcher.Invoke(() =>
        {
            try
            {
                // Pause media if needed
                _mediaControlManager?.PauseMediaIfNeeded();

                // Start recording
                var deviceId = SettingsManager.Instance.SelectedInputDeviceId;
                _audioRecorder?.StartRecording(deviceId);

                Log.Info($"Recording started - language: {language}, flag: {flag}");
            }
            catch (Exception ex)
            {
                Log.Error("Failed to start recording", ex);
            }
        });
    }

    private async void OnRecordingStop()
    {
        if (_isProcessingRecording) return;
        _isProcessingRecording = true;

        try
        {
            string? audioPath = null;
            string language = "en";

            Dispatcher.Invoke(() =>
            {
                audioPath = _audioRecorder?.StopRecording();
            });

            // Small delay for file to be finalized
            await Task.Delay(100);

            if (audioPath != null && File.Exists(audioPath))
            {
                Log.Info($"Processing recording: {audioPath}");

                // Determine language from the active slot
                var settings = SettingsManager.Instance;
                // Default to slot1 language
                language = settings.Slot1.Language;

                var result = await _whisperTranscriber!.Transcribe(audioPath, language);

                if (result != null)
                {
                    // Apply post-processing based on selected ModalConfig
                    result = TextPostProcessor.Apply(result, settings.ModalConfig);

                    Log.Info($"Transcription result: {result}");

                    // Add to history
                    settings.AddToHistory(result, language);

                    // Auto-paste
                    AutoPasteManager.CopyAndPaste(result);
                }
                else
                {
                    Log.Info("Transcription returned null (no speech detected)");
                }

                // Cleanup temp file
                AudioRecorder.CleanupTempFile(audioPath);
            }

            // Resume media
            _mediaControlManager?.ResumeMediaIfNeeded();
        }
        catch (Exception ex)
        {
            Log.Error("Error processing recording", ex);
        }
        finally
        {
            _isProcessingRecording = false;
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        Log.Info("Application shutting down");

        // Unregister hotkey
        if (_hwndSource?.Handle != IntPtr.Zero)
        {
            NativeMethods.UnregisterHotKey(_hwndSource!.Handle, SettingsHotkeyId);
        }
        _hwndSource?.Dispose();

        // Cleanup services
        _hotkeyManager?.Dispose();
        _audioRecorder?.Dispose();
        _trayIcon?.Dispose();
        _instanceMutex?.ReleaseMutex();
        _instanceMutex?.Dispose();

        base.OnExit(e);
    }
}
