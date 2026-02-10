#!/bin/bash
# Speech to Text - Kaldırma Scripti

PLIST_NAME="com.speechtotext.app"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"

echo "🗑️  Speech to Text Kaldırılıyor..."

# LaunchAgent'ı durdur
if launchctl list | grep -q "$PLIST_NAME"; then
    launchctl unload "$PLIST_PATH" 2>/dev/null
    echo "✓ Servis durduruldu"
fi

# Plist dosyasını sil
if [ -f "$PLIST_PATH" ]; then
    rm "$PLIST_PATH"
    echo "✓ LaunchAgent kaldırıldı"
fi

# Config dosyasını sil
if [ -f "$HOME/.speech_to_text_config.json" ]; then
    rm "$HOME/.speech_to_text_config.json"
    echo "✓ Ayarlar silindi"
fi

echo "✅ Kaldırma tamamlandı!"
