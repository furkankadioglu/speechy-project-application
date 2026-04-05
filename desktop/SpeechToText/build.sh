#!/bin/bash
# Speechy Build Script — auto-generates APP_BUILD with date, daily count, and time
# Usage: ./build.sh [--install]
#   --install: also replace binary in /Applications/Speechy.app and codesign

set -e
cd "$(dirname "$0")"

TODAY=$(date +%Y.%m.%d)
TIME=$(date +%H:%M)
COUNT_FILE=".build-count"

# Read previous build date and count
if [ -f "$COUNT_FILE" ]; then
    PREV_DATE=$(head -1 "$COUNT_FILE")
    PREV_COUNT=$(tail -1 "$COUNT_FILE")
else
    PREV_DATE=""
    PREV_COUNT=0
fi

# Increment or reset daily counter
if [ "$PREV_DATE" = "$TODAY" ]; then
    COUNT=$((PREV_COUNT + 1))
else
    COUNT=1
fi

# Save new count
echo "$TODAY" > "$COUNT_FILE"
echo "$COUNT" >> "$COUNT_FILE"

BUILD_STRING="${TODAY} #${COUNT} ${TIME}"

# Update APP_BUILD in main.swift
sed -i '' "s/^let APP_BUILD = .*/let APP_BUILD = \"${BUILD_STRING}\"/" main.swift

echo "Building Speechy — ${BUILD_STRING}"

# Compile
swiftc main.swift \
    -target arm64-apple-macosx12.0 \
    -o SpeechyApp \
    -framework Cocoa \
    -framework AVFoundation \
    -framework Carbon \
    -framework CoreAudio

echo "Build successful: SpeechyApp"

# Install if requested
if [ "$1" = "--install" ]; then
    cp SpeechyApp /Applications/Speechy.app/Contents/MacOS/SpeechyApp
    codesign --force --sign "Apple Development: Furkan Kadioglu (DQ27WAS8P2)" /Applications/Speechy.app
    echo "Installed and signed /Applications/Speechy.app"
fi
