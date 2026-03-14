# Windows Version

## Technology Stack
- **Language:** C# (.NET 8)
- **UI Framework:** WPF (Windows Presentation Foundation)
- **Audio:** NAudio 2.2.1
- **System Tray:** Hardcodet.NotifyIcon.Wpf 1.1.0
- **MVVM:** CommunityToolkit.Mvvm 8.2.2
- **Machine ID:** System.Management (WMI)
- **Whisper:** whisper-cli.exe subprocess (same as macOS approach)

## Project Location
`/windows/Speechy/` with solution at `/windows/Speechy.sln`

## Architecture
- MVVM pattern (ViewModels bind to Views via DataContext)
- Services layer (singletons matching macOS: SettingsManager, LicenseManager, HotkeyManager, etc.)
- All settings persisted to `%APPDATA%/Speechy/settings.json`
- Models stored in `%APPDATA%/Speechy/Models/`
- Logs to `%APPDATA%/Speechy/speechy_debug.log`

## Key Differences from macOS
- Global hotkeys: `SetWindowsHookEx(WH_KEYBOARD_LL)` instead of `CGEvent.tapCreate`
- Audio: NAudio `WaveInEvent` instead of `AVAudioEngine`
- System tray: `Hardcodet.NotifyIcon.Wpf` instead of `NSStatusBar`
- Auto-paste: `SendInput` Ctrl+V instead of `CGEvent` Cmd+V
- Settings hotkey: Ctrl+Shift+S instead of Cmd+Shift+S
- Launch at login: Registry `HKCU\...\Run` instead of `SMAppService`
- Media control: `VK_MEDIA_PLAY_PAUSE` via `keybd_event` instead of AppleScript
- Machine ID: WMI `Win32_ComputerSystemProduct` UUID instead of `IOPlatformUUID`

## UI Parity
All views are 1:1 copies of macOS SwiftUI views translated to WPF XAML:
- SplashWindow, LicenseWindow, OnboardingWindow, PermissionCheckWindow
- SettingsWindow with sidebar (Settings, Advanced, History, License tabs)
- OverlayWindow (transparent, always-on-top, click-through)
- WaveformControl (11 animated gradient bars)
- SlotConfigControl (hotkey slot configuration card)

## Build & Publish
```powershell
# Debug build
dotnet build windows/Speechy.sln

# Release publish (self-contained, single file)
dotnet publish windows/Speechy/Speechy.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true
```

## Database
Migration `004_add_windows_platform.sql` adds 'windows' to platform constraints.
Licensing API already accepts `app_platform: "windows"`.
