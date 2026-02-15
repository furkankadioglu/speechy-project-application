# Speechy Desktop

macOS menu bar app for speech-to-text. Records audio via configurable hotkeys, transcribes with whisper.cpp, and auto-pastes the result.

## Requirements

- macOS 12.0+
- [whisper-cpp](https://github.com/ggerganov/whisper.cpp) CLI: `brew install whisper-cpp`
- Accessibility permission (for global hotkeys)
- Microphone permission

## Build & Install

```bash
./build.sh
```

This compiles a universal binary (arm64 + x86_64), creates `Speechy.app` bundle, code-signs it, and copies to `/Applications`.

Manual build (without app bundle):
```bash
cd SpeechToText
swiftc main.swift -o SpeechyApp \
  -framework Cocoa -framework AVFoundation \
  -framework Carbon -framework CoreAudio
```

## Architecture

Single-file app (`SpeechToText/main.swift`, ~2500 lines):

```
AppDelegate (NSApplicationDelegate)
├── StatusItem (menu bar icon)
├── HotkeyManager (CGEvent tap for modifier keys)
├── AudioRecorder (AVAudioEngine → WAV file)
├── WhisperTranscriber (whisper-cli subprocess)
├── OverlayWindow (recording/processing indicator with waveform)
├── WaveformView (real-time audio level visualization)
├── SettingsManager (UserDefaults persistence)
├── AudioDeviceManager (CoreAudio device enumeration)
└── ModelDownloadManager (HuggingFace model download)

Views (SwiftUI hosted in NSWindow):
├── SplashView (startup animation)
├── OnboardingView (first-run setup)
├── SettingsView (TabView with settings/history)
│   ├── SettingsTab (hotkeys, model, audio device, preferences)
│   └── HistoryTab (past transcriptions)
└── SlotConfigView (per-slot hotkey configuration)
```

## Features

### Hotkey System
- 4 configurable slots with independent modifier key combinations
- Slot 1-2: Push-to-talk (hold modifier to record, release to stop)
- Slot 3-4: Toggle-to-talk (press modifier to start, press again or Escape to stop)
- Activation delay (default 150ms) prevents accidental triggers
- Per-slot language selection from 28 supported languages

### Whisper Models
Downloaded from HuggingFace to `~/Library/Application Support/Speechy/Models/`:

| Model | Size | Speed |
|-------|------|-------|
| Fast (Base) | ~150 MB | Fastest |
| Accurate (Small) | ~500 MB | Balanced |
| Precise (Medium) | ~1.5 GB | Most accurate |

Base model auto-downloads on first launch if no models exist.

### Audio
- Records via AVAudioEngine in native device format
- Converts offline to 16kHz mono 16-bit WAV for whisper-cli
- Selectable input device (auto-refreshes on device changes)

### Overlay & Waveform
- Recording state: flag emoji + animated waveform bars (7 vertical bars visualizing real-time audio RMS levels)
- Processing state: spinner animation
- Window floats at bottom center of screen (100x140px, rounded dark background)

### Transcription Flow
1. Hotkey detected → overlay shows flag emoji with waveform bars
2. Audio recording starts, waveform animates with real-time audio levels
3. Hotkey released/toggled or Escape pressed → overlay shows spinner
4. Audio saved to temp WAV, passed to `whisper-cli`
5. Non-speech patterns filtered (music, silence, applause markers)
6. Result copied to clipboard and auto-pasted (Cmd+V)
7. Transcription saved to history

### Supported Languages
Auto Detect, English, Turkish, German, French, Spanish, Italian, Portuguese, Dutch, Polish, Russian, Ukrainian, Japanese, Chinese, Korean, Arabic, Hindi, Swedish, Danish, Norwegian, Finnish, Greek, Czech, Romanian, Hungarian, Hebrew, Indonesian, Vietnamese, Thai

## Files

| File | Description |
|------|-------------|
| `SpeechToText/main.swift` | Entire app source code |
| `SpeechToText/Info.plist` | App metadata (bundle ID: `com.speechy.app`, LSUIElement) |
| `SpeechToText/SpeechToText.entitlements` | Audio input entitlement |
| `build.sh` | Build script (universal binary + app bundle + codesign) |

## Configuration

All settings stored in UserDefaults (`com.speechy.app`):

- Hotkey modifier keys and languages (4 slots)
- Selected Whisper model
- Audio input device
- Activation delay
- Launch at login
- Onboarding completion flag
- Transcription history

## Logs

Debug logs written to `/tmp/speechy_debug.log`.
