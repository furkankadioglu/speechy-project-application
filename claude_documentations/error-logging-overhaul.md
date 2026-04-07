# Error Logging & Robustness Overhaul (2026-04-08)

## Problem
Whisper transcription failing silently on other M1 Macs — empty result with no useful error info.

## Root Causes Found (15+ failure points)

### Critical
1. **Audio conversion failure silently passed to whisper** — `convertToWhisperFormat()` returned void, bad file still sent to whisper
2. **Model file only checked for existence** — 0-byte or partial downloads passed validation
3. **Force-unwrap crash risk** — `AVAudioPCMBuffer()!` in audio tap could crash under memory pressure
4. **No whisper process timeout** — `waitUntilExit()` could block forever if whisper hangs
5. **Stdout pipe read not concurrent** — potential deadlock if whisper wrote >64KB stdout

### High
6. **No input format validation** — devices could return 0Hz sample rate
7. **Silent buffer allocation failures** — conversion loop broke silently on OOM
8. **No recording duration tracking** — very short recordings (<0.3s) produced empty results with no warning
9. **No audio file size validation** — 0-byte files passed to whisper

### Medium
10. **Quarantine attributes on distribution** — Gatekeeper blocks execution on other Macs
11. **Insufficient stderr logging** — only 300 chars, truncated critical error info
12. **No exit code analysis** — crash signals (SIGKILL, SIGTERM) not distinguished from success
13. **Permission errors not detected** — Gatekeeper blocks with unhelpful message

## Fixes Applied

### AudioRecorder
- Input format validation (sample rate, channels)
- Safe buffer allocation (guard instead of force-unwrap)
- Recording duration logging + short recording warning
- Native file size check before conversion (abort if 0 bytes)
- Conversion buffer allocation failure logging

### ModelDownloadManager
- `modelExists()` now checks size > 1MB (catches corrupt/partial downloads)

### WhisperTranscriber
- Pre-flight validation: audio file exists + size > 100 bytes
- Pre-flight validation: model file exists + size logged
- Pre-flight validation: whisper binary is executable
- Concurrent stdout AND stderr reading (both via DispatchQueue)
- 120-second process timeout with forced termination
- Structured logging (language, model, audio, prompt, elapsed time)
- Full stderr logging (up to 20 lines, 200 chars each)
- Exit code analysis (0=success, -1/15=terminated, -9/9=OOM)
- Permission/quarantine error detection with fix instructions
- Non-zero exit + empty output = immediate failure (don't filter)

### Build Script
- `--deploy` flag: build + install + sign + zip + upload
- Correct signing order: frameworks → whisper-cli → app
- Quarantine attribute stripping for distribution

## Log Output (New)
```
[Speechy] Input format: 48000.0Hz, 1ch, float32
[Speechy] Recording stopped — duration: 3.45s
[Speechy] Native audio file: 345600 bytes (UUID_native.caf)
[Speechy] Source audio: 165888 frames, 48000.0Hz, 1ch, float32
[Speechy] Audio converted: 165888 frames @ 48000.0Hz -> 55296 frames @ 16kHz WAV
[Speechy] WAV file ready: 110636 bytes
[Speechy] ── Transcription start ──
[Speechy]   Language: en
[Speechy]   Model: medium (Precise (Medium))
[Speechy]   Audio: UUID.wav (110636 bytes)
[Speechy]   Model file: ggml-medium.bin (1533 MB)
[Speechy]   Whisper: /Applications/Speechy.app/.../whisper-cli
[Speechy] ── Whisper finished ──
[Speechy]   Exit code: 0 (took 2.3s)
[Speechy]   Stdout: 45 bytes
[Speechy]   Raw text: Hello, this is a test
[Speechy] ✓ Final result: Hello, this is a test
```
