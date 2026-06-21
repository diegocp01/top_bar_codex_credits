#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Codex Usage Menu Bar"
BUNDLE_ID="com.local.codex-usage-menu-bar"
VERSION="${VERSION:-0.1.0}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/.build/release}"
APP_DIR="$OUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BINARY="$MACOS_DIR/CodexUsageMenuBar"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ROOT_DIR/.build/module-cache"

env CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache" \
  clang "$ROOT_DIR/Sources/CodexUsageMenuBar/main.m" \
  -arch arm64 -arch x86_64 \
  -mmacosx-version-min=13.0 \
  -fobjc-arc \
  -framework Cocoa \
  -framework ServiceManagement \
  -O2 \
  -o "$BINARY"

if [[ -f /Applications/Codex.app/Contents/Resources/icon.icns ]]; then
  cp /Applications/Codex.app/Contents/Resources/icon.icns "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>CodexUsageMenuBar</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

find "$APP_DIR" -exec xattr -c {} + 2>/dev/null || true
codesign --force --sign "${CODESIGN_IDENTITY:--}" --options runtime "$APP_DIR" >/dev/null
find "$APP_DIR" -exec xattr -c {} + 2>/dev/null || true

echo "$APP_DIR"
