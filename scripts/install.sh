#!/usr/bin/env bash
# Build GlanceBar, install it as a menu-bar app, and register it to launch at login.
# No sudo required — everything lives under your home folder.
set -euo pipefail

APP_NAME="GlanceBar"
BUNDLE_ID="com.local.GlanceBar"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$HOME/Applications/$APP_NAME.app"
AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
U="$(id -u)"

echo "==> Building release binary"
cd "$REPO_DIR"
swift build -c release

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing"
codesign --force --sign - "$APP_DIR"

echo "==> Installing LaunchAgent (launch at login)"
mkdir -p "$(dirname "$AGENT")"
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>    <string>$BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array><string>$APP_DIR/Contents/MacOS/$APP_NAME</string></array>
    <key>RunAtLoad</key> <true/>
    <key>KeepAlive</key>
    <dict><key>SuccessfulExit</key> <false/></dict>
    <key>ProcessType</key> <string>Interactive</string>
    <key>LimitLoadToSessionType</key> <string>Aqua</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$U/$BUNDLE_ID" 2>/dev/null || true
launchctl bootstrap "gui/$U" "$AGENT"
launchctl enable "gui/$U/$BUNDLE_ID" 2>/dev/null || true

echo "==> Done. $APP_NAME is running and will start at login."
