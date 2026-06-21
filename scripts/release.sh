#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:?Set VERSION, for example VERSION=0.1.0}"
REPOSITORY="${GITHUB_REPOSITORY:-diegocp01/top_bar_codex_credits}"
APP_NAME="Codex Usage Menu Bar"
RELEASE_OUT_DIR="${RELEASE_OUT_DIR:-/private/tmp/codex-usage-menu-bar-release}"
APP_PATH="$RELEASE_OUT_DIR/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/.build/dist"
ZIP_PATH="$DIST_DIR/CodexUsageMenuBar-$VERSION-macOS-universal.zip"

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to your Developer ID Application identity}"
: "${APPLE_ID:?Set APPLE_ID for notarization}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID for notarization}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?Set APPLE_APP_SPECIFIC_PASSWORD for notarization}"

mkdir -p "$DIST_DIR"
rm -rf "$RELEASE_OUT_DIR"
OUT_DIR="$RELEASE_OUT_DIR" CODESIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" VERSION="$VERSION" "$ROOT_DIR/scripts/build.sh" >/dev/null

codesign --force --deep --strict --options runtime \
  --sign "$DEVELOPER_ID_APPLICATION" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait

xcrun stapler staple "$APP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo "$SHA256  $ZIP_PATH"
perl -0pi -e "s/sha256 (?:\"[a-f0-9]{64}\"|:no_check)/sha256 \"$SHA256\"/" \
  "$ROOT_DIR/Casks/codex-usage-menu-bar.rb"

if command -v gh >/dev/null 2>&1; then
  gh release create "v$VERSION" "$ZIP_PATH" \
    --repo "$REPOSITORY" \
    --title "v$VERSION" \
    --notes "Signed and notarized universal macOS app bundle."
else
  echo "Install GitHub CLI or upload $ZIP_PATH to https://github.com/$REPOSITORY/releases/tag/v$VERSION"
fi
