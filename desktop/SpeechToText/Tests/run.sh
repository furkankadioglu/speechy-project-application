#!/bin/bash
# run.sh — Speechy Desktop Test Runner
# Compiles all test files with -DTESTING and runs the TestRunner binary.

set -e
cd "$(dirname "$0")/.."   # cd into desktop/SpeechToText

mkdir -p .build-test

echo "Compiling test suite..."
swiftc \
    -DTESTING \
    -target arm64-apple-macosx12.0 \
    main.swift \
    Tests/*.swift \
    -o .build-test/TestRunner \
    -framework Cocoa \
    -framework AVFoundation \
    -framework Carbon \
    -framework CoreAudio

if [ $? -ne 0 ]; then
    echo "ERROR: Compilation failed"
    exit 1
fi

echo "Running tests..."
./.build-test/TestRunner
exit $?
