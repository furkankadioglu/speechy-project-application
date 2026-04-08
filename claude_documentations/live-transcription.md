# Live Transcription Feature

## Date: 2026-04-08

## Overview
Added real-time (live) transcription preview using periodic Whisper processing. When enabled, users see transcribed text updating every ~3 seconds during recording via a floating overlay window.

## Version Tag
- **v1.0.0** was tagged before this feature was implemented, allowing easy rollback if needed.
- Command to revert: `git checkout v1.0.0`

## Architecture

### How It Works
1. **Standard Mode (default)**: Record -> Stop -> Whisper processes full audio -> Paste result
2. **Live Mode (opt-in)**: Record + periodic Whisper preview every ~3s -> Text shown in overlay -> Stop -> Whisper processes full audio -> Paste final result

Both modes use Whisper for the final result — live mode just adds real-time preview during recording.

### New Classes

#### `LiveWhisperTranscriber`
- Accumulates audio buffers from `AudioRecorder`'s tap callback
- Every 3 seconds, writes accumulated buffers to temp .caf file
- Converts to 16kHz mono WAV via `afconvert`
- Runs `whisper-cli` on the accumulated audio
- Reports partial results via `onPartialResult` callback
- Thread-safe buffer accumulation with `NSLock`
- Skips tick if previous transcription is still processing

#### `LiveTextWindow`
- Floating translucent window (500x90px) positioned above the recording overlay
- Shows real-time partial transcription text
- Dark semi-transparent background with rounded corners
- Auto-repositions to screen center on show

### Modified Classes

#### `AudioRecorder`
- Added `onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?` callback
- Audio tap feeds copied buffers to both the file writer and the live transcriber

#### `SettingsManager`
- Added `isLiveTranscription: Bool` setting (persisted to UserDefaults, default: OFF)

#### `AppDelegate`
- `startRecording()`: When live mode is on, creates `LiveWhisperTranscriber`, shows `LiveTextWindow`, connects buffer callback
- `stopRecording()`: Stops live preview, then runs normal Whisper transcription for final result

#### `AdvancedTab`
- Added "Live Transcription" section with toggle

## Technical Details

- **Engine**: Same Whisper model used for both preview and final transcription
- **No extra permissions needed**: Uses existing microphone + whisper-cli
- **Preview interval**: ~3 seconds (skips if previous is still processing)
- **Final result**: Always from full audio Whisper processing (best quality)
- **No SFSpeechRecognizer**: Pure Whisper-based, no Apple Speech framework dependency

## Settings Location
Advanced tab > "Live Transcription" section > "Real-Time Transcription" toggle
