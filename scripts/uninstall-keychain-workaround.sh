#!/bin/bash
#
# Removes everything scripts/install-keychain-workaround.sh set up: the
# LaunchAgent, its copied script, logs, and the stored keychain-unlock
# password item.

set -euo pipefail

INSTALL_DIR="$HOME/.claude-status"
PLIST_DEST="$HOME/Library/LaunchAgents/com.bcollard.claudestatus.keychainfix.plist"
LOG_DIR="$HOME/Library/Logs/ClaudeStatus"
UNLOCK_SERVICE="ClaudeStatus-keychain-unlock"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

launchctl unload "$PLIST_DEST" >/dev/null 2>&1 || true
rm -f "$PLIST_DEST"
rm -rf "$INSTALL_DIR"
rm -rf "$LOG_DIR"
security delete-generic-password -a "$USER" -s "$UNLOCK_SERVICE" "$KEYCHAIN" >/dev/null 2>&1 || true

echo "Removed LaunchAgent, scripts, logs, and the stored unlock password."
