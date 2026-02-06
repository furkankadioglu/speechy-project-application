#!/bin/bash
# Speech to Text - macOS App Build Script

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/SpeechToText"
APP_NAME="Speechy"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🔨 Speech to Text Derleniyor..."
echo "================================"

# Eski build'i temizle
rm -rf "$APP_BUNDLE"

# App bundle yapısını oluştur
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Swift dosyasını derle (Universal Binary: arm64 + x86_64)
echo "📦 Derleniyor (arm64)..."
swiftc -O \
    -target arm64-apple-macos12.0 \
    -sdk $(xcrun --show-sdk-path) \
    -framework Cocoa \
    -framework AVFoundation \
    -framework Speech \
    -framework Carbon \
    -o "$MACOS_DIR/SpeechToText-arm64" \
    "$SRC_DIR/main.swift"

echo "📦 Derleniyor (x86_64)..."
swiftc -O \
    -target x86_64-apple-macos12.0 \
    -sdk $(xcrun --show-sdk-path) \
    -framework Cocoa \
    -framework AVFoundation \
    -framework Speech \
    -framework Carbon \
    -o "$MACOS_DIR/SpeechToText-x86_64" \
    "$SRC_DIR/main.swift"

echo "📦 Universal binary oluşturuluyor..."
lipo -create -output "$MACOS_DIR/SpeechToText" \
    "$MACOS_DIR/SpeechToText-arm64" \
    "$MACOS_DIR/SpeechToText-x86_64"

rm "$MACOS_DIR/SpeechToText-arm64" "$MACOS_DIR/SpeechToText-x86_64"

# Info.plist kopyala
cp "$SRC_DIR/Info.plist" "$CONTENTS_DIR/"

# Entitlements uygula (codesign için)
echo "🔏 İmzalanıyor..."
codesign --force --sign - --entitlements "$SRC_DIR/SpeechToText.entitlements" "$APP_BUNDLE"

echo ""
echo "✅ Derleme tamamlandı!"

# /Applications'a kopyala (izinlerin kalıcı olması için)
cp -r "$APP_BUNDLE" /Applications/
echo "📂 /Applications/Speechy.app güncellendi"
echo ""
echo "🚀 Çalıştırmak için:"
echo "   open /Applications/Speechy.app"
