#!/bin/bash
#
# Installs the opt-in Keychain-partition-list workaround (see CLAUDE.md
# "Known limitations" #2). Stores your login keychain password in a
# dedicated, separate Keychain item, then installs a LaunchAgent that
# periodically re-grants ClaudeStatus's Keychain ACL trust on the
# "Claude Code-credentials" item so the "wants to access" prompt stops
# recurring.
#
# This is NOT run by build.sh / the app itself — it's a standalone,
# explicit opt-in. Run scripts/uninstall-keychain-workaround.sh to remove
# everything it sets up.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="$HOME/.claude-status"
SCRIPT_DEST="$INSTALL_DIR/keychain-partition-fix.sh"
PLIST_DEST="$HOME/Library/LaunchAgents/com.bcollard.claudestatus.keychainfix.plist"
LOG_DIR="$HOME/Library/Logs/ClaudeStatus"
UNLOCK_SERVICE="ClaudeStatus-keychain-unlock"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

echo "This stores your login keychain password as a Keychain item (service"
echo "'$UNLOCK_SERVICE'), readable only by this workaround, so a LaunchAgent"
echo "can re-apply ClaudeStatus's Keychain trust every 10 minutes without a"
echo "GUI prompt. The password is passed to /usr/bin/security as a command"
echo "line argument each run, which is transiently visible to other local"
echo "processes on this Mac (e.g. via 'ps'). See CLAUDE.md for the tradeoffs."
echo
read -r -p "Continue? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo
read -r -s -p "Login keychain password: " KEYCHAIN_PASSWORD
echo
if [ -z "$KEYCHAIN_PASSWORD" ]; then
    echo "Empty password, aborting." >&2
    exit 1
fi

# Verify it's actually the login keychain password before storing it.
if ! security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "That didn't unlock $KEYCHAIN — aborting, nothing was stored." >&2
    exit 1
fi

# Replace any previous copy of the stored password.
security delete-generic-password -a "$USER" -s "$UNLOCK_SERVICE" "$KEYCHAIN" >/dev/null 2>&1 || true
security add-generic-password \
    -a "$USER" -s "$UNLOCK_SERVICE" \
    -w "$KEYCHAIN_PASSWORD" \
    -T "/usr/bin/security" \
    -U \
    "$KEYCHAIN"
unset KEYCHAIN_PASSWORD

mkdir -p "$INSTALL_DIR" "$LOG_DIR"
cp "$REPO_DIR/scripts/keychain-partition-fix.sh" "$SCRIPT_DEST"
chmod +x "$SCRIPT_DEST"

sed \
    -e "s#__SCRIPT_PATH__#$SCRIPT_DEST#g" \
    -e "s#__LOG_DIR__#$LOG_DIR#g" \
    -e "s#__KEYCHAIN_DB__#$KEYCHAIN#g" \
    "$REPO_DIR/LaunchAgents/com.bcollard.claudestatus.keychainfix.plist.template" \
    >"$PLIST_DEST"

launchctl unload "$PLIST_DEST" >/dev/null 2>&1 || true
launchctl load "$PLIST_DEST"

echo
echo "Installed and loaded. It runs immediately, then every 10 minutes."
echo "Logs: $LOG_DIR/keychain-partition-fix.log"
echo "Uninstall with: $REPO_DIR/scripts/uninstall-keychain-workaround.sh"
