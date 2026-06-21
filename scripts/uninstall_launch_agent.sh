#!/usr/bin/env bash
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.local.codex-usage-menu-bar.plist"

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"

echo "Uninstalled Codex Usage Menu Bar"
