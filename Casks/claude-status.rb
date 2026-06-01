cask "claude-status" do
  version "0.1.0"
  # Replace with the sha256 printed at the end of scripts/release.sh.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/bcollard/claude-status-macos-menu-bar/releases/download/v#{version}/ClaudeStatus.dmg"
  name "Claude Status"
  desc "macOS menu bar app that monitors Claude Code usage"
  homepage "https://github.com/bcollard/claude-status-macos-menu-bar"

  depends_on macos: ">= :sonoma"

  app "ClaudeStatus.app"

  zap trash: [
    "~/Library/Preferences/com.bcollard.claudestatus.plist",
  ]

  caveats <<~EOS
    Claude Status reads your Claude Code OAuth credentials from the macOS Keychain
    entry "Claude Code-credentials". The first time you open the dropdown, macOS
    will ask you to grant access — choose "Always Allow".
  EOS
end
