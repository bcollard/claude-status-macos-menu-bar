cask "claude-status" do
  version "0.2.3"
  sha256 "16fc18f23c8440f0ac1c96b3f028469de593683531c17f40c44d0a586f069a53"

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
