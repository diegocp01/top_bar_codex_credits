#!/usr/bin/env bash
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.local.codex-usage-menu-bar.plist"

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"

echo "Removed legacy Codex Usage Menu Bar LaunchAgent if present"
echo "If you also enabled the app menu item Launch at Login, disable it from the menu bar app."
