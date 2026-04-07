#!/bin/bash
# Speechy Build Script — auto-generates APP_BUILD with date, daily count, and time
# Usage: ./build.sh [--install] [--deploy]
#   --install: also replace binary in /Applications/Speechy.app and codesign
#   --deploy:  install + zip + upload to speechy.frkn.com.tr

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

SIGN_ID="Apple Development: Furkan Kadioglu (DQ27WAS8P2)"
APP_PATH="/Applications/Speechy.app"

# Install if requested
if [ "$1" = "--install" ] || [ "$1" = "--deploy" ]; then
    cp SpeechyApp "$APP_PATH/Contents/MacOS/SpeechyApp"

    # Sign frameworks first, then binaries, then app
    for dylib in "$APP_PATH"/Contents/Frameworks/*.dylib; do
        codesign --force --sign "$SIGN_ID" "$dylib" 2>/dev/null
    done
    codesign --force --sign "$SIGN_ID" "$APP_PATH/Contents/MacOS/whisper-cli"
    codesign --force --sign "$SIGN_ID" "$APP_PATH"

    # Remove quarantine attributes so the binary runs on other Macs
    find "$APP_PATH" -exec xattr -c {} \; 2>/dev/null || true

    echo "Installed and signed $APP_PATH"
fi

# Deploy if requested
if [ "$1" = "--deploy" ]; then
    echo "Deploying to speechy.frkn.com.tr..."
    cd /tmp
    rm -rf Speechy.app Speechy.zip
    cp -R "$APP_PATH" /tmp/Speechy.app
    # Remove quarantine from the copy too
    find /tmp/Speechy.app -exec xattr -c {} \; 2>/dev/null || true
    zip -r Speechy.zip Speechy.app
    scp Speechy.zip yuksel:/Domains/speechy.frkn.com.tr/public_html/Speechy.zip
    rm -rf Speechy.app Speechy.zip
    echo "Deployed: speechy.frkn.com.tr/Speechy.zip"
fi
