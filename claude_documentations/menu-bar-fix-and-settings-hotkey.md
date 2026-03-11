# Menu Bar Icon Fix & Global Settings Hotkey

## Problem
- Speechy was running but the menu bar icon (microphone) was not appearing
- App was not visible in the Dock either (by design, but also couldn't access UI)
- No way to access the settings window

## Root Cause
The app is built as a plain binary (`swiftc main.swift -o SpeechyApp`), not as a `.app` bundle. Because of this, the `Info.plist` (which contains `LSUIElement=true`) was never read by macOS. Without a proper activation policy, macOS didn't handle the status bar item correctly.

## Changes Made

### 1. Programmatic Activation Policy (`main.swift` - Main section)
Added `app.setActivationPolicy(.accessory)` before `app.run()`. This:
- Hides the app from the Dock (same effect as `LSUIElement=true`)
- Properly sets up the app as a menu bar (accessory) app
- Works without needing a `.app` bundle

### 2. Robust Status Bar Setup (`setupStatusBar()`)
- Added `isTemplate = true` to the SF Symbol image so it adapts to light/dark menu bar
- Added fallback emoji icon if SF Symbol fails
- Replaced direct click action with a proper `NSMenu` containing:
  - "Settings... (Cmd+Shift+S)" - opens settings window
  - "Quit Speechy" - exits the app

### 3. Global Keyboard Shortcut (`registerSettingsHotkey()`)
- Registered **Cmd+Shift+S** as a global hotkey using Carbon `RegisterEventHotKey`
- Works from anywhere, even when no window is visible
- Posts `OpenSettings` notification which is already observed by the app

## Testing
- Build succeeds without errors
- 57/58 tests pass (1 pre-existing failure unrelated to this change)
