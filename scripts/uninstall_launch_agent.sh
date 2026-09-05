#!/usr/bin/env bash
set -euo pipefail

# Preserve the opt-out even when the app is opened manually again.
defaults write com.local.codex-usage-menu-bar launchAtLoginPreference -bool false
for label in com.local.autostart.codex-usage com.local.codex-usage-menu-bar; do
  if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)/$label"
  fi
  rm -f "$HOME/Library/LaunchAgents/$label.plist"
done
echo "Disabled Codex automatic startup and restart."
