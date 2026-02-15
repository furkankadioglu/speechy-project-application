#!/bin/bash
# Speechy Desktop — Test Runner
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/SpeechToText"
BUILD_DIR="$SRC_DIR/.build-test"

mkdir -p "$BUILD_DIR"

echo "Compiling tests..."
swiftc -DTESTING \
    -target arm64-apple-macos12.0 \
    -sdk $(xcrun --show-sdk-path) \
    -framework Cocoa \
    -framework AVFoundation \
    -framework Carbon \
    -framework CoreAudio \
    -o "$BUILD_DIR/TestRunner" \
    "$SRC_DIR/main.swift" \
    "$SRC_DIR/Tests/DesktopTests.swift"

echo "Running tests..."
echo ""
"$BUILD_DIR/TestRunner"
