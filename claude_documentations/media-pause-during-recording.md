# Media Pause During Recording Feature

## Date: 2026-03-14

## Overview
Added a feature that automatically pauses music/media playback when the user starts recording (speech-to-text) and resumes it when the transcription is complete.

## Changes Made

### 1. MediaControlManager Class (`main.swift`)
- New singleton class `MediaControlManager` added after `AudioDeviceManager`
- **Media detection**: Uses `NSAppleScript` to check if Music or Spotify is currently playing
- **Media control**: Simulates the system media play/pause key press using `NSEvent.otherEvent` with `NX_KEYTYPE_PLAY` (key code 16) via `CGEvent.post`
- **State tracking**: Tracks whether it was the one that paused media (`didPauseMedia` flag) so it only resumes playback if it initiated the pause
- Methods:
  - `pauseMediaIfNeeded()` - Called when recording starts
  - `resumeMediaIfNeeded()` - Called when transcription ends
  - `reset()` - Resets internal state

### 2. SettingsManager Updates
- Added `@Published var pauseMediaDuringRecording: Bool` property
- Default value is `true` (enabled by default)
- Persisted via UserDefaults with key `"pauseMediaDuringRecording"`
- Auto-save observer added for the property

### 3. UI Toggle in Advanced Tab
- Added a toggle in the "General" section of the Advanced settings tab
- Icon: `pause.circle.fill` in pink color
- Toggle tint: pink
- Description: "Automatically pause music when recording and resume when done"

### 4. Recording Flow Integration (AppDelegate)
- `startRecording()`: Calls `MediaControlManager.shared.pauseMediaIfNeeded()` before starting the audio recorder
- `stopRecording()`: Calls `MediaControlManager.shared.resumeMediaIfNeeded()` after transcription completes (in the `DispatchQueue.main.async` block), covering both successful transcription and error/empty cases

## Technical Approach
- Uses AppleScript to detect playback state of Music and Spotify apps
- Uses CGEvent system media key simulation (NX_KEYTYPE_PLAY) for universal play/pause control that works with any media player
- The media key approach is preferred because it works with all media players (Apple Music, Spotify, YouTube in browser, etc.) without needing to target specific apps
- AppleScript detection is only used for the initial "is something playing?" check

## Build Command
```bash
cd desktop/SpeechToText && swiftc main.swift -o SpeechyApp -framework Cocoa -framework AVFoundation -framework Carbon -framework CoreAudio
```

Build verified successfully with no errors.
