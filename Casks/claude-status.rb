cask "claude-status" do
  version "0.2.1"
  sha256 "0f41d2d13860d1624140dae4965e6d4d86987301aaeb8e7c5ab518801aeb94b9"

  url "https://github.com/bcollard/claude-status-macos-menu-bar/releases/download/v#{version}/ClaudeStatus.dmg"
  name "Claude Status"
  desc "Menu bar app that monitors Claude Code usage"
  homepage "https://github.com/bcollard/claude-status-macos-menu-bar"

  depends_on macos: :sonoma

  app "ClaudeStatus.app"

  zap trash: "~/Library/Preferences/com.bcollard.claudestatus.plist"

  caveats <<~EOS
    Claude Status reads your Claude Code OAuth credentials from the macOS Keychain
    entry "Claude Code-credentials". The first time you open the dropdown, macOS
    will ask you to grant access — choose "Always Allow".
  EOS
end
