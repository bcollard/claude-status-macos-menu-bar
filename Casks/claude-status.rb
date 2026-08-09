cask "claude-status" do
  version "0.1.1"
  sha256 "e044b9af302fbe7070ab1c77d5cab79420176e76213a05556f6027e1e204c51f"

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
