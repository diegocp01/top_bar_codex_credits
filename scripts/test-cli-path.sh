#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/.build/cli-path-tests"
clang -fobjc-arc -mmacosx-version-min=13.0 -framework Foundation \
  -I "$ROOT/Sources/CodexUsageMenuBar" "$ROOT/Tests/CodexCLIPathTests.m" \
  -o "$ROOT/.build/cli-path-tests/CodexCLIPathTests"
"$ROOT/.build/cli-path-tests/CodexCLIPathTests"
