#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/.build/release"

mkdir -p "$OUT_DIR" "$ROOT_DIR/.build/module-cache"

env CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache" \
  clang "$ROOT_DIR/Sources/CodexUsageMenuBar/main.m" \
  -fobjc-arc \
  -framework Cocoa \
  -O2 \
  -o "$OUT_DIR/CodexUsageMenuBar"

echo "$OUT_DIR/CodexUsageMenuBar"
