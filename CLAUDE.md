# Speechy Project - Claude Code Configuration

## Performance & Agent Settings
- ALWAYS use parallel agent execution when tasks are independent
- Launch multiple sub-agents concurrently for research, exploration, and code tasks
- Use `subagent_type=Explore` for codebase exploration tasks
- Use `subagent_type=Plan` for architecture planning
- Prefer background agents (`run_in_background: true`) for independent tasks while continuing foreground work
- No token conservation — use as much context as needed for thorough analysis
- Always use `effortLevel: high` — provide comprehensive, detailed responses
- When multiple files need to be read, read them all in parallel
- When multiple searches are needed, run them all in parallel
- When multiple edits are independent, make them all in parallel

## Build Commands
- Desktop (universal binary — Intel + Apple Silicon):
  ```
  cd desktop/SpeechToText
  swiftc main.swift -target arm64-apple-macosx12.0 -o SpeechyApp-arm64 -framework Cocoa -framework AVFoundation -framework Carbon -framework CoreAudio
  swiftc main.swift -target x86_64-apple-macosx12.0 -o SpeechyApp-x86 -framework Cocoa -framework AVFoundation -framework Carbon -framework CoreAudio
  lipo -create SpeechyApp-arm64 SpeechyApp-x86 -output SpeechyApp
  rm SpeechyApp-arm64 SpeechyApp-x86
  ```
- Mobile: `cd mobile && xcodebuild build -scheme Speechy -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
- Mobile tests: `cd mobile && xcodebuild test -scheme Speechy -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`

## Language
- Respond in Turkish when user writes in Turkish
- Code comments and commit messages in English
