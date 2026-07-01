cask "claude-status" do
  version "0.1.0"
  sha256 "f7eed5693844da2e0f1151ae9326ee2d12903ab510710df735af882297d7d5e8"

  url "https://github.com/bcollard/claude-status-macos-menu-bar/releases/download/v#{version}/ClaudeStatus.dmg"
  name "Claude Status"
  desc "macOS menu bar app that monitors Claude Code usage"
  homepage "https://github.com/bcollard/claude-status-macos-menu-bar"

  depends_on macos: :sonoma

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
