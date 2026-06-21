#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/.build/release/Codex Usage Menu Bar.app"
LEGACY_PLIST="$HOME/Library/LaunchAgents/com.local.codex-usage-menu-bar.plist"

if [[ ! -d "$APP_PATH" ]]; then
  "$ROOT_DIR/scripts/build.sh" >/dev/null
fi

if [[ -f "$LEGACY_PLIST" ]]; then
  launchctl bootout "gui/$(id -u)" "$LEGACY_PLIST" >/dev/null 2>&1 || true
  rm -f "$LEGACY_PLIST"
fi

open "$APP_PATH"

cat <<MSG
LaunchAgent installation is no longer used.
Use the app menu item "Launch at Login" to enable startup via SMAppService.
MSG
