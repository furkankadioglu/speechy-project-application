# Permission Check & License UX Improvements

## Date: 2026-03-14

## Changes Made

### 1. Permission Check on Every Launch
- Added `checkPermissions()` global helper function that returns `(accessibility: Bool, microphone: Bool)` tuple
- Uses `AXIsProcessTrusted()` for Accessibility and `AVCaptureDevice.authorizationStatus(for: .audio)` for Microphone
- Called in `initializeFullApp()` BEFORE setting up hotkeys
- If either permission is missing, shows the dedicated permission check window

### 2. PermissionCheckView (SwiftUI)
- Dedicated permission check window (440x520) with clear visual design
- Shows each permission with green checkmark (granted) or red X (missing) indicators
- Explains WHY each permission is needed in simple language
- "Open System Settings" button opens the correct Settings pane (Accessibility or Microphone)
- "Check Again" button re-checks permissions and continues if all granted
- "Continue" button appears when all permissions are granted

### 3. Hotkey Listener Resilience
- Updated `HotkeyManager.showAccessibilityPrompt()` to show the new PermissionCheckView window instead of a basic NSAlert
- Falls back to the old NSAlert if AppDelegate is not available

### 4. Cmd+Shift+S Always Works
- Moved the `OpenSettings` notification observer to `initializeApp()` so it's registered before license check
- Added `handleSettingsHotkey()` method that routes to license screen if no license, or settings if licensed
- The Cmd+Shift+S hotkey now always functions regardless of license state

### 5. App Flow
- Splash screen -> License check -> Permission check -> Full app init
- `initializeFullApp()` now calls `continueFullAppInit()` after permissions pass
- `showPermissionCheck()` creates the permission window and continues to `continueFullAppInit()` on success

## Files Modified
- `desktop/SpeechToText/main.swift`

## Build Command
```bash
cd desktop/SpeechToText && swiftc main.swift -o SpeechyApp -framework Cocoa -framework AVFoundation -framework Carbon -framework CoreAudio
```
