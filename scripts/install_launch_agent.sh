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
"$BUILT_APP_PATH/Contents/MacOS/CodexUsageMenuBar" --pause-startup
launchctl bootout "gui/$(id -u)/com.local.codex-usage-menu-bar" >/dev/null 2>&1 || true
rm -f "$PLIST"
pkill -x CodexUsageMenuBar >/dev/null 2>&1 || true
rm -rf "$APP_PATH"
ditto --noqtn "$BUILT_APP_PATH" "$APP_PATH"
xattr -cr "$APP_PATH" 2>/dev/null || true
codesign --force --sign - --options runtime "$APP_PATH" >/dev/null
codesign --verify --deep --strict "$APP_PATH"

open "$APP_PATH"
echo "Installed $APP_PATH"
echo "The app enables Launch at Login & Keep Running by default. Disable it in the app menu to keep Quit permanent."
