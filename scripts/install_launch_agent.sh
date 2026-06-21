#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="$ROOT_DIR/.build/release/CodexUsageMenuBar"
PLIST="$HOME/Library/LaunchAgents/com.local.codex-usage-menu-bar.plist"

if [[ ! -x "$BINARY" ]]; then
  "$ROOT_DIR/scripts/build.sh"
fi

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.local.codex-usage-menu-bar</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BINARY</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CODEX_USAGE_READER</key>
    <string>$ROOT_DIR/scripts/read_codex_usage.py</string>
  </dict>
  <key>StandardOutPath</key>
  <string>/tmp/codex-usage-menu-bar.out.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/codex-usage-menu-bar.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/com.local.codex-usage-menu-bar"
launchctl kickstart -k "gui/$(id -u)/com.local.codex-usage-menu-bar"

echo "Installed: $PLIST"
