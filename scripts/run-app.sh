#!/bin/bash
# Membangun Montase Studio sebagai aplikasi .app dan membukanya.
# Pemakaian: ./scripts/run-app.sh [--no-open]
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Montase Studio.app"
BIN="$APP/Contents/MacOS"

swift build -c release
EXE="$(swift build -c release --show-bin-path)/MontaseStudio"

rm -rf "$APP"
mkdir -p "$BIN" "$APP/Contents/Resources"
cp "$EXE" "$BIN/MontaseStudio"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Montase Studio</string>
    <key>CFBundleDisplayName</key><string>Montase Studio</string>
    <key>CFBundleIdentifier</key><string>com.khincc.montase-studio</string>
    <key>CFBundleExecutable</key><string>MontaseStudio</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>NSSpeechRecognitionUsageDescription</key><string>Montase Studio mengenali ucapan di video di Mac ini untuk fitur Auto Clip. Tidak ada audio yang dikirim keluar.</string>
</dict>
</plist>
PLIST

# Tanda tangan ad-hoc agar macOS mau menjalankan bundle yang dibangun secara lokal.
codesign --force --sign - "$APP" >/dev/null

echo "Aplikasi dibangun di: $APP"
if [[ "${1:-}" != "--no-open" ]]; then
    open "$APP"
fi
