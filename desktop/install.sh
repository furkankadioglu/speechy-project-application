#!/bin/bash
# Speech to Text - Kurulum Scripti

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_NAME="com.speechtotext.app"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"

echo "🎤 Speech to Text Kurulumu"
echo "=========================="

# Python bağımlılıklarını kur
echo "📦 Bağımlılıklar yükleniyor..."
pip3 install -r "$SCRIPT_DIR/requirements.txt" --quiet

# LaunchAgent plist oluştur
echo "⚙️  LaunchAgent ayarlanıyor..."
cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>${SCRIPT_DIR}/speech_app.py</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${SCRIPT_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/speechtotext.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/speechtotext.err</string>
</dict>
</plist>
EOF

echo "✅ Kurulum tamamlandı!"
echo ""
echo "📋 Kullanım:"
echo "  Başlat:  launchctl load $PLIST_PATH"
echo "  Durdur:  launchctl unload $PLIST_PATH"
echo "  Manuel:  python3 $SCRIPT_DIR/speech_app.py"
echo ""
echo "⚠️  ÖNEMLİ: System Preferences'dan şu izinleri verin:"
echo "  - Security & Privacy > Privacy > Accessibility"
echo "  - Security & Privacy > Privacy > Microphone"
echo ""
echo "🚀 Şimdi başlatmak için:"
echo "  launchctl load $PLIST_PATH"
