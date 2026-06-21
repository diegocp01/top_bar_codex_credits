cask "codex-usage-menu-bar" do
  version "0.1.0"
  sha256 :no_check

  url "https://github.com/diegocp01/top_bar_codex_credits/releases/download/v#{version}/CodexUsageMenuBar-#{version}-macOS-universal.zip"
  name "Codex Usage Menu Bar"
  desc "Menu bar monitor for Codex rate limits and credits"
  homepage "https://github.com/diegocp01/top_bar_codex_credits"

  depends_on macos: ">= :ventura"

  app "Codex Usage Menu Bar.app"

  zap trash: [
    "~/Library/Preferences/com.local.codex-usage-menu-bar.plist",
    "~/Library/LaunchAgents/com.local.codex-usage-menu-bar.plist",
  ]
end
