# Speechy

On-device speech-to-text for macOS, Windows, and iOS. Uses [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for fully offline transcription — no cloud services, no API keys, no internet required (except for initial model download).

## Components

```
speechy-project-application/
├── desktop/    macOS menu bar app (Swift, whisper-cli)
├── windows/    Windows system tray app (C#, WPF, .NET 8)
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
cd desktop/SpeechToText
./build.sh                    # Build only
./build.sh --install          # Build + replace /Applications/Speechy.app + codesign
./build.sh --deploy           # Install + zip + upload to speechy.frkn.com.tr
./build.sh --app-store        # Sandboxed Mac App Store build (-DAPP_STORE, .pkg)
open /Applications/Speechy.app
```

The `--app-store` build emits `build-appstore/Speechy.pkg` ready for App Store Connect upload. Receipt validation gates the binary; non-buyers cannot run it. See [claude_documentations/app-store-distribution.md](claude_documentations/app-store-distribution.md).

**Manual Build** (without build script):
```bash
cd desktop/SpeechToText
swiftc main.swift -o SpeechyApp \
  -framework Cocoa -framework AVFoundation \
  -framework Carbon -framework CoreAudio
```

### Windows — System Tray App

System tray app for Windows that transcribes speech to text via configurable hotkeys and auto-pastes the result. Mirrors macOS app functionality.

- **Framework**: C# / WPF / .NET 8
- **Hotkeys**: 4 configurable slots — 2 push-to-talk, 2 toggle-to-talk (low-level keyboard hook)
- **Languages**: 29 languages with per-slot language selection
- **Models**: 4 tiers — Fast (Base), Accurate (Small), Precise (Medium), Ultimate (Large)
- **Audio Input**: NAudio WaveInEvent, records to 16kHz mono PCM WAV
- **Auto-paste**: Clipboard + SendInput Ctrl+V simulation
- **History**: All transcriptions saved with language and timestamp
- **System Tray**: Runs in system tray with Ctrl+Shift+S for settings
- **Licensing**: Same license system as macOS (speechy.frkn.com.tr)

**Requirements**: Windows 10+, .NET 8.0 Runtime, [whisper-cli.exe](https://github.com/ggerganov/whisper.cpp)

**Build & Run**:
```bash
cd windows
dotnet build
dotnet run --project Speechy/Speechy.csproj
```

**Publish** (self-contained single file):
```bash
cd windows
dotnet publish -c Release -r win-x64 --self-contained
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

**Desktop (macOS)** uses whisper-cpp CLI as a subprocess, records to WAV file, passes file path.
**Windows** uses whisper-cli.exe as a subprocess via NAudio for recording, same approach as macOS.
**Mobile** uses SwiftWhisper (whisper.cpp Swift wrapper) in-process, with CoreML Neural Engine acceleration.

## Quick Start

```bash
# Desktop
brew install whisper-cpp
cd desktop && ./build.sh
./test.sh                             # Run 58 tests
open /Applications/Speechy.app

# Windows
cd windows && dotnet build

# Mobile
cd mobile
xcodebuild -resolvePackageDependencies -project Speechy.xcodeproj
open Speechy.xcodeproj  # Build & run on physical device
```
