#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_OUT_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/codex-usage-menu-bar.XXXXXX")"
trap 'rm -rf "$BUILD_OUT_DIR"' EXIT
BUILT_APP_PATH="$BUILD_OUT_DIR/Codex Usage Menu Bar.app"
APP_PATH="${APP_PATH:-$HOME/Applications/Codex Usage Menu Bar.app}"
PLIST="$HOME/Library/LaunchAgents/com.local.codex-usage-menu-bar.plist"

OUT_DIR="$BUILD_OUT_DIR" "$ROOT_DIR/scripts/build.sh" >/dev/null

mkdir -p "$(dirname "$APP_PATH")"
pkill -x CodexUsageMenuBar >/dev/null 2>&1 || true
rm -rf "$APP_PATH"
ditto --noqtn "$BUILT_APP_PATH" "$APP_PATH"
xattr -cr "$APP_PATH" 2>/dev/null || true
codesign --force --sign - --options runtime "$APP_PATH" >/dev/null
codesign --verify --deep --strict "$APP_PATH"

mkdir -p "$(dirname "$PLIST")"

cat >"$PLIST" <<PLIST_XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.local.codex-usage-menu-bar</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-g</string>
    <string>$APP_PATH</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
PLIST_XML

plutil -lint "$PLIST" >/dev/null
launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/com.local.codex-usage-menu-bar"
launchctl kickstart -k "gui/$(id -u)/com.local.codex-usage-menu-bar"

open "$APP_PATH"

cat <<MSG
Installed Codex Usage Menu Bar LaunchAgent:
$PLIST
Installed app:
$APP_PATH
MSG
