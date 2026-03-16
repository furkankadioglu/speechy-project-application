# Hotkey System Upgrade - Key+Modifier Combination Support

## Date: 2026-03-16

## Summary
Upgraded the hotkey system from modifier-only hotkeys (e.g., just pressing Option) to support ANY key or key combination (e.g., Cmd+Shift+T, Ctrl+K, F5, etc.) while maintaining full backward compatibility.

## Changes Made

### 1. HotkeyConfig (Data Model)
- Added `keyCode: Int64` field (default `-1` = modifier-only mode, `>= 0` = specific key required)
- Added `isModifierOnly` computed property for clarity
- Updated `displayName` to append the key name when a key is set (e.g., "Command+Shift+T")
- Added `static func keyName(for:)` that maps macOS virtual key codes to human-readable names
  - Covers all letters (A-Z), numbers (0-9), F-keys (F1-F15), arrow keys, special keys (Space, Tab, Return, Delete, Esc), and common punctuation

### 2. SlotConfigView (UI)
- Added "Shortcut Key" section below modifier toggles
- Shows current key name or "Modifier only" when no key is set
- "Set Key" button enters recording mode to capture the next key press
- "x" button clears the key (reverts to modifier-only mode)
- Created `ShortcutKeyRecorder` (NSViewRepresentable) and `ShortcutKeyRecorderView` (NSView) for capturing key presses in the SwiftUI settings view

### 3. HotkeyManager (Event Handling)
- Event mask updated to include `keyUp` in addition to `flagsChanged` and `keyDown`
- Renamed `matchesConfig` to `matchesModifiers` (checks only modifier flags)
- `handleEvent` now has three sections:
  - **keyDown**: Handles key+modifier configs (start recording, toggle stop); Escape still stops toggle recording
  - **keyUp**: Handles key+modifier push-to-talk release (stop recording); resets toggle ignore flag
  - **flagsChanged**: Handles modifier-only configs exactly as before (no behavioral change)
- Trigger key events are consumed (return `nil`) to prevent them from reaching other apps

### 4. Backward Compatibility
- Existing configs with no `keyCode` field decode to `-1` (modifier-only) via Codable default
- All modifier-only behavior is completely unchanged
- The `flagsChanged` section only processes modifier-only configs
- The `keyDown`/`keyUp` sections only process key+modifier configs

## Technical Details
- macOS virtual key codes are used (same as `event.keyCode` / `CGEvent.getIntegerValueField(.keyboardEventKeycode)`)
- Modifier-only keys (Shift, Control, Option, Command) are filtered out from the key recorder to prevent confusion
- The event tap uses `.defaultTap` option which allows consuming events by returning `nil`

## Build
```
cd desktop/SpeechToText && swiftc main.swift -o SpeechyApp -framework Cocoa -framework AVFoundation -framework Carbon -framework CoreAudio
```
Build succeeds with zero warnings.
