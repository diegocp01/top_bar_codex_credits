#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/.build/startup-tests"
clang -fobjc-arc -mmacosx-version-min=13.0 -framework Foundation -framework ServiceManagement \
  -I "$ROOT/Sources/CodexUsageMenuBar" "$ROOT/Tests/StartupTests.m" \
  -o "$ROOT/.build/startup-tests/StartupTests"
"$ROOT/.build/startup-tests/StartupTests"
