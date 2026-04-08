# Live Transcription Feature

## Date: 2026-04-08

## Overview
Added real-time (live) transcription mode using Apple's `SFSpeechRecognizer` framework. When enabled, users see transcribed text appearing in real-time as they speak, similar to Apple's built-in dictation feature.

## Version Tag
- **v1.0.0** was tagged before this feature was implemented, allowing easy rollback if needed.
- Command to revert: `git checkout v1.0.0`

## Architecture

### Two Transcription Modes
1. **Standard Mode (default)**: Record -> Stop -> Whisper AI processes -> Paste result
2. **Live Mode (new, opt-in)**: Record + SFSpeechRecognizer -> Real-time text in overlay -> Instant paste on stop

### New Classes

#### `LiveTranscriber`
- Wraps `SFSpeechRecognizer` and `SFSpeechAudioBufferRecognitionRequest`
- Receives audio buffers from `AudioRecorder`'s tap callback
- Reports partial results via `onPartialResult` callback
- Prefers on-device recognition when available (macOS 13+) for lower latency
- Handles permission requests via static `requestPermission()` method

#### `LiveTextWindow`
- Floating translucent window (500x90px) positioned above the recording overlay
- Shows real-time partial transcription text
- Dark semi-transparent background with rounded corners
- Auto-repositions to screen center on show

### Modified Classes

#### `AudioRecorder`
- Added `onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?` callback
- Audio tap now feeds buffers to both the file writer and the live transcriber

#### `SettingsManager`
- Added `isLiveTranscription: Bool` setting (persisted to UserDefaults, default: OFF)

#### `AppDelegate`
- `startRecording()`: When live mode is on, creates `LiveTranscriber`, shows `LiveTextWindow`, feeds audio buffers
- `stopRecording()`: When live mode is on, gets result from speech recognizer instantly (no Whisper processing), hides overlay and text window

#### `AdvancedTab`
- Added "Live Transcription" section with toggle, icon, and info text about permission requirements

## Technical Details

- **Framework**: `Speech` (Apple's SFSpeechRecognizer)
- **Permission**: Speech Recognition permission is requested on first use
- **On-device**: Uses on-device recognition when available (no network needed)
- **Language support**: Uses the same language code from the active hotkey slot
- **No Whisper dependency**: Live mode bypasses Whisper entirely for instant results

## Settings Location
Advanced tab > "Live Transcription" section > "Real-Time Transcription" toggle
