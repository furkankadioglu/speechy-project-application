# Auto-Paste Setting

## Summary
Added a new setting to control whether transcribed text is automatically pasted into the active application after speech-to-text conversion.

## Changes
- **New setting: `autoPasteText`** in `SettingsManager` (default: OFF)
- Previously, transcribed text was always copied to clipboard and auto-pasted via simulated Cmd+V
- Now this behavior is opt-in — users must enable "Auto-Paste Transcription" in Settings
- The setting is persisted in UserDefaults under the key `autoPasteText`

## UI
- Toggle added to the Settings tab, under the "Save Audio Recordings" option
- Orange-themed toggle with `doc.on.clipboard.fill` icon
- Description: "Automatically paste transcribed text into the active app using Cmd+V"

## Technical Details
- The `pasteText()` function is now guarded by `SettingsManager.shared.autoPasteText`
- Manual copy buttons (History tab, Logs tab) are NOT affected — they always work
- Transcription still gets saved to History regardless of this setting

## Date
2026-04-04
