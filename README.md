# Codex Usage Menu Bar

Small macOS menu-bar utility that shows live Codex usage limits, reset timing, credits, and available usage resets next to the clock.

<p>
  <img src="assets/menu-bar-preview.png" alt="Codex Usage Menu Bar countdown preview" width="284">
  <img src="assets/menu-bar-battery-preview.png" alt="Codex Usage Menu Bar battery preview" width="284">
</p>

The app uses Codex app-server as its live source through `account/rateLimits/read`. It understands the current multi-bucket snapshot shape, including secondary windows, monthly account limits, credits, and `rateLimitResetCredits`. If app-server is unavailable, it falls back to reading recent local Codex JSONL session events from `~/.codex/sessions`.

No Python runtime is required by the app.

Click the menu-bar item to choose:

- Percentage or battery display.
- Percentage left or percentage used. The default is percentage left.
- Reset clock time or a live countdown to reset.
- Refresh interval: 30 seconds, 1 minute, 3 minutes, or 5 minutes.
- Launch at Login, backed by `SMAppService`.

## Install

No notarized GitHub Release has been published yet. For now, build the local `.app`:

```sh
./scripts/build.sh
open ".build/release/Codex Usage Menu Bar.app"
```

After a signed and notarized GitHub Release is published, it can be installed by downloading the release `.app` or with Homebrew:

```sh
brew tap diegocp01/top_bar_codex_credits https://github.com/diegocp01/top_bar_codex_credits
brew install --cask codex-usage-menu-bar
```

Use the app menu item **Launch at Login** to start it automatically through macOS `SMAppService`. It does not use `KeepAlive`, so choosing **Quit** stays quit.

For local development builds, you can also install a per-user LaunchAgent that opens the built app at login:

```sh
./scripts/install_launch_agent.sh
```

This LaunchAgent only runs `open` during login. It does not use `KeepAlive`, so choosing **Quit** stays quit until the next login or manual launch.

## Build Locally

```sh
./scripts/build.sh
open ".build/release/Codex Usage Menu Bar.app"
```

The build script produces a universal Apple Silicon/Intel `.app` bundle and ad-hoc signs it for local use. This local build is not notarized.

## Release

Set the signing and notarization environment variables, then run:

```sh
VERSION=0.1.0 \
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="TEAMID" \
APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
./scripts/release.sh
```

The release script builds the universal app, signs it with hardened runtime, submits it to Apple notarization, staples the app, creates the release zip, writes the SHA-256 into `Casks/codex-usage-menu-bar.rb`, and uploads a GitHub Release when `gh` is installed.

## Legacy LaunchAgent Cleanup

To remove the local development LaunchAgent:

```sh
./scripts/uninstall_launch_agent.sh
```
