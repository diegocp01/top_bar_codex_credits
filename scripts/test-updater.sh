#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/.build/updater-tests"
clang -fobjc-arc -mmacosx-version-min=13.0 -framework Foundation \
  -I "$ROOT/Sources/CodexUsageMenuBar" "$ROOT/Tests/UpdaterTests.m" \
  -o "$ROOT/.build/updater-tests/UpdaterTests"
"$ROOT/.build/updater-tests/UpdaterTests"
