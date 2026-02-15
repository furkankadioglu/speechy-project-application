# Speechy

On-device speech-to-text for macOS and iOS. Uses [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for fully offline transcription — no cloud services, no API keys, no internet required (except for initial model download).

## Components

```
speechy-project-application/
├── desktop/    macOS menu bar app (Swift, whisper-cli)
└── mobile/     iOS app (SwiftUI, SwiftWhisper)
```

### Desktop — macOS Menu Bar App

Menu bar app that transcribes speech to text via configurable hotkeys and automatically pastes the result.

- **Hotkeys**: 4 configurable slots — 2 push-to-talk, 2 toggle-to-talk (Escape to cancel)
- **Live Waveform**: Real-time audio level visualization in overlay during recording
- **Languages**: 29 languages with per-slot language selection
- **Models**: 3 tiers — Fast (Base ~150MB), Accurate (Small ~500MB), Precise (Medium ~1.5GB)
- **Audio Input**: Selectable input device with live device change detection
- **Auto-paste**: Transcribed text is copied to clipboard and pasted automatically (Cmd+V)
- **History**: All transcriptions saved with language and timestamp
- **Launch at Login**: Optional, via SMAppService

**Requirements**: macOS 12.0+, [whisper-cpp](https://github.com/ggerganov/whisper.cpp) CLI (`brew install whisper-cpp`), Accessibility permission (for hotkeys), Microphone permission

**Build & Run**:
```bash
cd desktop
./build.sh                    # Builds universal binary, copies to /Applications
open /Applications/Speechy.app
```

**Manual Build** (without build script):
```bash
cd desktop/SpeechToText
swiftc main.swift -o SpeechyApp \
  -framework Cocoa -framework AVFoundation \
  -framework Carbon -framework CoreAudio
```

### Mobile — iOS App

Standalone iOS app with on-device Whisper transcription using Apple Neural Engine acceleration.

- **Model**: Whisper Small Q5_1 (~181MB) with CoreML encoder (~168MB bundled)
- **Language**: Turkish (hardcoded)
- **UI**: Two tabs — Recording and History
- **Offline**: Fully on-device after model download

**Requirements**: iOS 16.0+, Xcode 15.0+, ~350MB storage

See [mobile/README.md](mobile/README.md) for detailed documentation.

## Architecture

Both apps follow the same pattern:

1. Audio captured from microphone (16kHz mono PCM)
2. Whisper model transcribes audio to text locally
3. Result displayed/pasted — no network calls involved

**Desktop** uses whisper-cpp CLI as a subprocess, records to WAV file, passes file path.
**Mobile** uses SwiftWhisper (whisper.cpp Swift wrapper) in-process, with CoreML Neural Engine acceleration.

## Quick Start

```bash
# Desktop
brew install whisper-cpp
cd desktop && ./build.sh
./test.sh                             # Run 58 tests
open /Applications/Speechy.app

# Mobile
cd mobile
xcodebuild -resolvePackageDependencies -project Speechy.xcodeproj
open Speechy.xcodeproj  # Build & run on physical device
```
