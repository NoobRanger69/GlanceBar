#!/usr/bin/env bash
# Stop GlanceBar, remove its LaunchAgent and the installed app bundle.
set -euo pipefail

APP_NAME="GlanceBar"
BUNDLE_ID="com.local.GlanceBar"
U="$(id -u)"

launchctl bootout "gui/$U/$BUNDLE_ID" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
rm -rf "$HOME/Applications/$APP_NAME.app"

echo "$APP_NAME uninstalled. (Source tree left untouched.)"
