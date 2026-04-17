# Desktop Test Suite

## Overview
A comprehensive client-side test suite for the Speechy macOS desktop app compiled with `swiftc -DTESTING`. No XCTest or Xcode project required. All 175 assertions pass with zero network or hardware dependencies.

## Files

- `desktop/SpeechToText/Tests/DesktopTests.swift` — Main test file (~500 lines). Custom assert harness + all test groups.
- `desktop/SpeechToText/Tests/run.sh` — Entry point. Compiles and runs the TestRunner.

## Running Tests

```bash
bash desktop/SpeechToText/Tests/run.sh
```

Compilation command used:
```bash
swiftc -DTESTING -target arm64-apple-macosx12.0 main.swift Tests/*.swift \
  -o .build-test/TestRunner \
  -framework Cocoa -framework AVFoundation -framework Carbon -framework CoreAudio
```

## Test Groups (175 total assertions)

| Group | Assertions | Description |
|---|---|---|
| HotkeyConfig | 20 | displayName, isModifierOnly, keyCode paths, escCancels, Codable, keyName samples |
| ModelType | 11 | displayName, fileName, sizeBytes, rawValues, CaseIterable count=2 |
| TranscriptionEntry | 9 | init, Codable roundtrip, unique IDs, dates, audioURL |
| AudioInputDevice | 3 | systemDefault uid/name/isDefault |
| Supported Languages | 4 | count=29, auto first, unique codes, non-empty flags |
| filterNonSpeech | 15 | [BLANK_AUDIO], [MUSIC], Müzik, Altyazı M.K., musical symbols, speech dominance |
| getFlag | 4 | en, tr, unknown, auto |
| matchesModifiers | 7 | exact match, no modifiers, superset, missing modifier, key+modifier variants |
| SettingsManager History | 8 | add, order, reject blank/short, cap=50, delete, clear |
| HotkeyConfig Extended | 5 | configForID, updateConfigs replaces slots |
| HotkeyManager | 8 | stopListening idempotent, deinit safe, cooldown ~0.5s, callbacks fire |
| SettingsManager Extended | 27 | whisperPrompt, wave params, activationDelay, selectedModel, isCapturingShortcut, slots persistence, clearHistory |
| LicenseManager | 10 | storedLicenseKey getter/setter, isLicensed flip, offline startup, machineID cache |
| AudioRecorder | 8 | writeErrorLogged reset, stopRecording no-start nil, double-stop nil |
| LiveWhisperTranscriber | 15 | removeRepetitions (7 cases), appendBuffer before start, stop on never-started, start+stop race |
| filterNonSpeech Extended | 14 | Altyazı M.K. variants, silence patterns, applause, subtitle attribution |
| Hotkey Recording Pipeline | 9 | end-to-end: configForID, start/stop callbacks, cooldown after stop |

## Hooks Added to main.swift

All under `#if TESTING` — zero behavior change in production:

| Class | Hook | Purpose |
|---|---|---|
| `SettingsManager` | `init(forTesting:)` — added missing `showInDock` | Fix compile error: published var was missing from test init |
| `HotkeyManager` | `testCooldownUntil: Date` | Expose cooldown for timing assertions |
| `HotkeyManager` | `testConfigForID(_:)` | Expose private `configForID` for lookup tests |
| `HotkeyManager` | `testSimulateRecordingCycle(language:flag:)` | Simulate start+stop without CGEvent tap |
| `HotkeyManager` | `testSetConfigs(_:activationDelay:)` | Inject slot list without touching SettingsManager.shared |
| `AudioRecorder` | `testWriteErrorLogged: Bool` | Expose write-error flag for reset-on-start assertion |
| `LicenseManager` | `init(testDefaults:)` | Inject isolated UserDefaults suite to avoid polluting real prefs |
| `LicenseManager` | `defaults` backing store | Refactored from hardcoded `UserDefaults.standard` to injectable field |
| `LiveWhisperTranscriber` | `testRemoveRepetitions(_:)` | Expose private dedup method for unit testing |
| `LiveWhisperTranscriber` | `testIsStopped: Bool` | Expose stop state for lifecycle assertions |

## Deferred / Stubbed Tests

- **Network license flows** (`verifyAndActivate`, `activate`, `deactivate`): require live API. These are exercised via manual integration testing.
- **Real microphone recording**: `AudioRecorder.startRecording` with a real device hits AVAudioEngine's hardware path — tested only for the reset-on-start flag and the no-prior-start behavior.
- **CGEvent tap creation**: `HotkeyManager.startListening` requires Accessibility permission. Tested via `testSimulateRecordingCycle` instead.

## Issues Found in Production Code

1. **`SettingsManager(forTesting:)` was missing `showInDock`** — the `@Published var showInDock: Bool` was not initialized in the test init, causing a compile error. Fixed by adding `_showInDock = Published(initialValue: true)`.
2. **`LicenseManager` used hardcoded `UserDefaults.standard`** in `machineID` save path and `init()` — makes it impossible to test without polluting real defaults. Refactored to a `defaults: UserDefaults` field (injectable via `#if TESTING` init).
