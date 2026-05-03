#!/bin/bash
# Speechy Build Script — auto-generates APP_BUILD with date, daily count, and time
# Usage: ./build.sh [--install] [--deploy] [--app-store]
#   --install:   replace binary in /Applications/Speechy.app and codesign
#   --deploy:    install + zip + upload to speechy.frkn.com.tr
#   --app-store: build sandboxed App Store variant with -DAPP_STORE, package as .pkg
#                signed with Mac App Distribution cert for App Store Connect upload

set -e
cd "$(dirname "$0")"

MODE="$1"

TODAY=$(date +%Y.%m.%d)
TIME=$(date +%H:%M)
COUNT_FILE=".build-count"

if [ -f "$COUNT_FILE" ]; then
    PREV_DATE=$(head -1 "$COUNT_FILE")
    PREV_COUNT=$(tail -1 "$COUNT_FILE")
else
    PREV_DATE=""
    PREV_COUNT=0
fi

if [ "$PREV_DATE" = "$TODAY" ]; then
    COUNT=$((PREV_COUNT + 1))
else
    COUNT=1
fi

echo "$TODAY" > "$COUNT_FILE"
echo "$COUNT" >> "$COUNT_FILE"

BUILD_STRING="${TODAY} #${COUNT} ${TIME}"
sed -i '' "s/^let APP_BUILD = .*/let APP_BUILD = \"${BUILD_STRING}\"/" main.swift

SIGN_ID="Apple Development: Furkan Kadioglu (DQ27WAS8P2)"
APP_PATH="/Applications/Speechy.app"

# ============================================================================
# App Store build
# ============================================================================
if [ "$MODE" = "--app-store" ]; then
    echo "Building Speechy App Store variant — ${BUILD_STRING}"

    # Distribution cert names — change if your team uses different ones
    APP_DIST_ID="${SPEECHY_MAS_APP_CERT:-3rd Party Mac Developer Application: Furkan Kadioglu (DQ27WAS8P2)}"
    INSTALLER_DIST_ID="${SPEECHY_MAS_INSTALLER_CERT:-3rd Party Mac Developer Installer: Furkan Kadioglu (DQ27WAS8P2)}"
    PROVISIONING_PROFILE="${SPEECHY_MAS_PROFILE:-./Speechy_Mac_App_Store.provisionprofile}"

    BUILD_DIR="./build-appstore"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR/Speechy.app/Contents/MacOS"
    mkdir -p "$BUILD_DIR/Speechy.app/Contents/Resources"
    mkdir -p "$BUILD_DIR/Speechy.app/Contents/Frameworks"

    # Compile with APP_STORE flag
    swiftc main.swift \
        -target arm64-apple-macosx12.0 \
        -DAPP_STORE \
        -O \
        -o "$BUILD_DIR/Speechy.app/Contents/MacOS/SpeechyApp" \
        -framework Cocoa \
        -framework AVFoundation \
        -framework Carbon \
        -framework CoreAudio

    # Use App Store Info.plist (sandboxed, with required keys)
    cp Info.AppStore.plist "$BUILD_DIR/Speechy.app/Contents/Info.plist"

    # Copy resources from current installed app
    if [ -d "$APP_PATH/Contents/Resources" ]; then
        cp -R "$APP_PATH/Contents/Resources/." "$BUILD_DIR/Speechy.app/Contents/Resources/"
    fi
    if [ -d "$APP_PATH/Contents/Frameworks" ]; then
        cp -R "$APP_PATH/Contents/Frameworks/." "$BUILD_DIR/Speechy.app/Contents/Frameworks/"
    fi
    if [ -f "$APP_PATH/Contents/MacOS/whisper-cli" ]; then
        cp "$APP_PATH/Contents/MacOS/whisper-cli" "$BUILD_DIR/Speechy.app/Contents/MacOS/whisper-cli"
    fi

    # Embed provisioning profile (required for Mac App Store submission)
    if [ -f "$PROVISIONING_PROFILE" ]; then
        cp "$PROVISIONING_PROFILE" "$BUILD_DIR/Speechy.app/Contents/embedded.provisionprofile"
    else
        echo "WARNING: provisioning profile not found at $PROVISIONING_PROFILE"
        echo "         Build will work for local sandbox testing but cannot be uploaded to App Store Connect."
    fi

    # Sign frameworks and binaries with App Store entitlements
    for dylib in "$BUILD_DIR/Speechy.app/Contents/Frameworks/"*.dylib; do
        [ -f "$dylib" ] && codesign --force --sign "$APP_DIST_ID" --options runtime "$dylib"
    done
    if [ -f "$BUILD_DIR/Speechy.app/Contents/MacOS/whisper-cli" ]; then
        codesign --force --sign "$APP_DIST_ID" --options runtime \
            --entitlements SpeechToText.AppStore.entitlements \
            "$BUILD_DIR/Speechy.app/Contents/MacOS/whisper-cli"
    fi
    codesign --force --sign "$APP_DIST_ID" --options runtime \
        --entitlements SpeechToText.AppStore.entitlements \
        "$BUILD_DIR/Speechy.app"

    # Verify signature
    codesign --verify --deep --strict --verbose=2 "$BUILD_DIR/Speechy.app"

    # Build installer pkg for App Store Connect upload
    PKG_PATH="$BUILD_DIR/Speechy.pkg"
    productbuild --component "$BUILD_DIR/Speechy.app" /Applications \
        --sign "$INSTALLER_DIST_ID" \
        "$PKG_PATH"

    echo ""
    echo "App Store build complete."
    echo "  App: $BUILD_DIR/Speechy.app"
    echo "  Pkg: $PKG_PATH"
    echo ""
    echo "Upload to App Store Connect:"
    echo "  xcrun altool --upload-app --type osx --file \"$PKG_PATH\" \\"
    echo "      --apple-id YOUR_APPLE_ID --password APP_SPECIFIC_PASSWORD"
    echo ""
    exit 0
fi

# ============================================================================
# Standard (direct distribution) build
# ============================================================================
echo "Building Speechy — ${BUILD_STRING}"

swiftc main.swift \
    -target arm64-apple-macosx12.0 \
    -o SpeechyApp \
    -framework Cocoa \
    -framework AVFoundation \
    -framework Carbon \
    -framework CoreAudio

echo "Build successful: SpeechyApp"

if [ "$MODE" = "--install" ] || [ "$MODE" = "--deploy" ]; then
    cp SpeechyApp "$APP_PATH/Contents/MacOS/SpeechyApp"

    for dylib in "$APP_PATH"/Contents/Frameworks/*.dylib; do
        codesign --force --sign "$SIGN_ID" "$dylib" 2>/dev/null
    done
    codesign --force --sign "$SIGN_ID" "$APP_PATH/Contents/MacOS/whisper-cli"
    codesign --force --sign "$SIGN_ID" "$APP_PATH"

    find "$APP_PATH" -exec xattr -c {} \; 2>/dev/null || true

    echo "Installed and signed $APP_PATH"
fi

if [ "$MODE" = "--deploy" ]; then
    echo "Deploying to speechy.frkn.com.tr..."
    cd /tmp
    rm -rf Speechy.app Speechy.zip
    cp -R "$APP_PATH" /tmp/Speechy.app
    find /tmp/Speechy.app -exec xattr -c {} \; 2>/dev/null || true
    zip -r Speechy.zip Speechy.app
    scp Speechy.zip yuksel:/Domains/speechy.frkn.com.tr/public_html/Speechy.zip
    rm -rf Speechy.app Speechy.zip
    echo "Deployed: speechy.frkn.com.tr/Speechy.zip"
fi
