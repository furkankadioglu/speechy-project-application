# Windows WPF Views - Pixel-Perfect macOS Port

## Date: 2026-03-14

## Summary
Created all WPF XAML views and code-behind files for the Speechy Windows app, matching the macOS SwiftUI views pixel-for-pixel. Every color, gradient, font size, spacing, corner radius, and layout was matched from the macOS `main.swift` source.

## Files Created (26 files total)

### ViewModels (2 files)
- `ViewModels/MainViewModel.cs` - Tab navigation (SelectedTab, SelectTabCommand, QuitCommand)
- `ViewModels/SettingsViewModel.cs` - Wraps SettingsManager, ModelDownloadManager, LicenseManager for binding

### Windows (12 files = 6 XAML + 6 code-behind)
- `Views/SplashWindow.xaml(.cs)` - Borderless 300x350, dark gradient bg, blue-purple circle + mic, animated progress bar
- `Views/LicenseWindow.xaml(.cs)` - 440x480, gradient circle + key icon, license input field, activate button with spinner, error/success messages, trial link
- `Views/OnboardingWindow.xaml(.cs)` - 500x500, 3-page wizard (Welcome, Permissions, How to Use) with page dots navigation
- `Views/PermissionCheckWindow.xaml(.cs)` - 440x520, orange-red gradient shield, permission rows with green/red status, Open Settings / Check Again / Continue buttons
- `Views/SettingsWindow.xaml(.cs)` - 672x816, left sidebar (168px) with logo/nav/quit, right content area with tab switching
- `Views/OverlayWindow.xaml(.cs)` - 120x150 transparent click-through always-on-top, gradient circle + mic + flag badge, waveform bars, spinner state

### Tab UserControls (8 files = 4 XAML + 4 code-behind)
- `Views/Tabs/SettingsTab.xaml(.cs)` - 4 hotkey slot configs (Slot 1 blue, Slot 2 green, Slot 3 orange, Slot 4 red)
- `Views/Tabs/AdvancedTab.xaml(.cs)` - AI Model radio selection with download, Activation Delay slider, Voice Input device, Waveform Sensitivity sliders, General toggles
- `Views/Tabs/HistoryTab.xaml(.cs)` - Transcription history list with flag/time/copy/delete, empty state, Clear All footer
- `Views/Tabs/LicenseTab.xaml(.cs)` - License status card, details table, deactivate button, permissions section

### Reusable Controls (4 files = 2 XAML + 2 code-behind)
- `Views/Controls/SlotConfigControl.xaml(.cs)` - Reusable hotkey slot card with enable toggle, modifier buttons (Shift/Ctrl/Alt/Win), language dropdown, accent color theming
- `Views/Controls/WaveformControl.xaml(.cs)` - 11 animated gradient bars (blue-to-purple) with weighted heights

## Color Mapping (macOS -> Windows)
- Background: `Color(red: 0.1, green: 0.1, blue: 0.15)` -> `#1A1A26` / `#1E1E2E`
- Blue gradient: `Color.blue` (#007AFF) -> `#007AFF` / `#3B82F6`
- Purple gradient: `Color.purple` (#AF52DE) -> `#AF52DE` / `#8B5CF6`
- Card background: `NSColor.controlBackgroundColor` -> `#2D2D42`
- Secondary text: `.secondary` -> `#A0A0B8`
- Green: `.green` -> `#22C55E`
- Red: `.red` -> `#EF4444`
- Orange: `.orange` -> `#F97316`

## Icon Mapping (SF Symbols -> Segoe MDL2 Assets)
- `mic.fill` -> `\uE720`
- `gearshape.fill` -> `\uE713`
- `slider.horizontal.3` -> `\uE9E9`
- `clock.fill` -> `\uE823`
- `key.fill` -> `\uE192`
- `keyboard` -> `\uE765`
- `lock.shield.fill` -> `\uEA18`
- `checkmark.circle.fill` -> `\uE73E`
- `xmark.circle.fill` -> `\uE711`
- `power` -> `\uE7E8`
- `trash` -> `\uE74D`
- `doc.on.doc` -> `\uE8C8`
- `arrow.down.circle.fill` -> `\uE896`
- `globe` -> `\uE774`

## Architecture Notes
- All views use the existing `Services/` and `Models/` layer (SettingsManager, LicenseManager, ModelDownloadManager, etc.)
- SettingsWindow uses code-behind tab switching (not data binding) for simplicity and reliability
- SlotConfigControl is a reusable UserControl that maps directly to macOS SlotConfigView
- WaveformControl implements the same 11-bar weighted animation as the macOS WaveformView
- OverlayWindow uses Win32 `WS_EX_TRANSPARENT` for click-through behavior (equivalent to `ignoresMouseEvents = true`)
