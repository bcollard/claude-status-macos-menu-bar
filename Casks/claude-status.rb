cask "claude-status" do
  version "0.1.0"
  # Replace with the output of `shasum -a 256 ClaudeStatus-<version>.zip`
  # printed by scripts/release.sh.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  # Replace YOUR_GH_USERNAME with your GitHub username (or org).
  url "https://github.com/YOUR_GH_USERNAME/claude-status-macos-menu-bar/releases/download/v#{version}/ClaudeStatus-#{version}.zip"
  name "Claude Status"
  desc "macOS menu bar app that monitors Claude Code usage"
  homepage "https://github.com/YOUR_GH_USERNAME/claude-status-macos-menu-bar"

  depends_on macos: ">= :sonoma"

  app "Claude Status.app"

  zap trash: [
    "~/Library/Preferences/com.bcollard.claudestatus.plist",
  ]

  caveats <<~EOS
    Claude Status reads your Claude Code OAuth credentials from the macOS Keychain
    entry "Claude Code-credentials". The first time you open the dropdown, macOS
    will ask you to grant access — choose "Always Allow".

    This build is unsigned. The first launch may show a Gatekeeper warning; right-
    click the app in Finder and choose "Open" to confirm.
  EOS
end
