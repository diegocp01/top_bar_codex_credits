#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/.build/release/Codex Usage Menu Bar.app"
PLIST="$HOME/Library/LaunchAgents/com.local.codex-usage-menu-bar.plist"

if [[ ! -d "$APP_PATH" ]]; then
  "$ROOT_DIR/scripts/build.sh" >/dev/null
fi

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
MSG
