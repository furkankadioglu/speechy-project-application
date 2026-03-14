# Windows App Project Setup

## Date: 2024-03-14

## Summary
Created the complete C# / WPF / .NET 8 project structure for the Speechy Windows desktop application. This mirrors the macOS desktop app's architecture and functionality.

## Files Created

### Solution & Project
- `windows/Speechy.sln` - .NET solution file
- `windows/Speechy/Speechy.csproj` - .NET 8 WPF project with NuGet packages (NAudio 2.2.1, Hardcodet.NotifyIcon.Wpf 1.1.0, CommunityToolkit.Mvvm 8.2.2, System.Management 8.0.0)

### Models (4 files)
- `Models/HotkeyConfig.cs` - HotkeyMode enum, ModifierKeys flags, HotkeyConfig class
- `Models/WhisperModel.cs` - WhisperModel enum with extension methods for display names, file names, download URLs, sizes
- `Models/SupportedLanguage.cs` - 29 languages matching macOS app exactly (auto, en, tr, de, fr, es, it, pt, nl, pl, ru, uk, ja, zh, ko, ar, hi, sv, da, no, fi, el, cs, ro, hu, he, id, vi, th)
- `Models/TranscriptionEntry.cs` - Transcription history entry with Id, Text, Language, Flag, CreatedAt

### Services (10 files)
- `Services/Logger.cs` - Singleton logger writing to %APPDATA%/Speechy/speechy_debug.log
- `Services/SettingsManager.cs` - Singleton settings persisted to JSON, all properties matching macOS app
- `Services/MachineIdProvider.cs` - WMI UUID with Registry fallback for machine identification
- `Services/LicenseManager.cs` - License activation/verification/deactivation via speechy.frkn.com.tr API
- `Services/WhisperTranscriber.cs` - Runs whisper-cli.exe subprocess with non-speech filtering
- `Services/ModelDownloadManager.cs` - HuggingFace model download with progress, stored in %APPDATA%/Speechy/Models/
- `Services/AudioRecorder.cs` - NAudio WaveInEvent recording to 16kHz mono PCM WAV
- `Services/HotkeyManager.cs` - Low-level keyboard hook for modifier-only hotkeys with activation delay
- `Services/MediaControlManager.cs` - Media play/pause control via VK_MEDIA_PLAY_PAUSE
- `Services/AutoPasteManager.cs` - Clipboard + SendInput Ctrl+V simulation

### Helpers (2 files)
- `Helpers/NativeMethods.cs` - P/Invoke for SetWindowsHookEx, RegisterHotKey, SendInput, keybd_event
- `Helpers/RelayCommand.cs` - Standard ICommand + AsyncRelayCommand for MVVM

### App Entry Point (2 files)
- `App.xaml` - Application definition with Styles.xaml resource dictionary
- `App.xaml.cs` - Startup flow: Mutex single-instance, splash, license check, tray icon, Ctrl+Shift+S hotkey

### Resources (1 file)
- `Resources/Styles.xaml` - Dark theme color palette (blues/purples matching macOS), button styles, card styles, input styles

## Architecture
- All services are singletons matching the macOS app pattern
- Settings stored as JSON in %APPDATA%/Speechy/
- License API uses app_platform="windows"
- 4 hotkey slots with push-to-talk and toggle-to-talk modes
- Low-level keyboard hook for modifier-only key detection
- Whisper transcription via subprocess (whisper-cli.exe)
