#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/.build/pace-tests"
clang -fobjc-arc -mmacosx-version-min=13.0 -framework Foundation \
  -I "$ROOT/Sources/CodexUsageMenuBar" "$ROOT/Tests/UsagePaceTests.m" \
  -o "$ROOT/.build/pace-tests/UsagePaceTests"
"$ROOT/.build/pace-tests/UsagePaceTests"
