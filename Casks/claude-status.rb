cask "claude-status" do
  version "0.2.2"
  sha256 "1d7f9d39394ddb90f63f34351e3b94a0de254e81304e43d6e29f1ec293370db5"

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
