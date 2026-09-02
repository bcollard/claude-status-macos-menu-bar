#!/bin/bash
#
# Re-grants ClaudeStatus's Keychain ACL trust on the "Claude Code-credentials"
# item. Claude Code periodically rewrites that item (token refresh / SSO
# re-bootstrap); the rewrite resets the item's trusted-app partition list, so
# the "Always Allow" grant from the GUI prompt doesn't stick. This script
# re-applies the partition list so the prompt doesn't come back.
#
# Not part of the ClaudeStatus app or its default install — opt-in via
# scripts/install-keychain-workaround.sh. See CLAUDE.md "Known limitations"
# for the tradeoffs (this reads a Keychain-stored password and passes it to
# `security` on the command line, which is transiently visible to other
# local processes via `ps`).

set -euo pipefail

SERVICE="Claude Code-credentials"
ACCOUNT="claude-code-user"
UNLOCK_SERVICE="ClaudeStatus-keychain-unlock"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
LOG_DIR="$HOME/Library/Logs/ClaudeStatus"
LOG_FILE="$LOG_DIR/keychain-partition-fix.log"
TEAM_ID="PZARL6555S"
PARTITION_LIST="apple-tool:,apple:,teamid:${TEAM_ID}"

mkdir -p "$LOG_DIR"
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $1" >>"$LOG_FILE"; }

# Nothing to do if Claude Code hasn't written this item (yet).
if ! security find-generic-password -a "$ACCOUNT" -s "$SERVICE" "$KEYCHAIN" >/dev/null 2>&1; then
    log "no '$SERVICE' item found for account '$ACCOUNT' — skipping"
    exit 0
fi

UNLOCK_PASSWORD="$(security find-generic-password -a "$USER" -s "$UNLOCK_SERVICE" -w "$KEYCHAIN" 2>>"$LOG_FILE")"
if [ -z "$UNLOCK_PASSWORD" ]; then
    log "no stored unlock password found under service '$UNLOCK_SERVICE' — run install-keychain-workaround.sh"
    exit 1
fi

if security set-generic-password-partition-list \
    -a "$ACCOUNT" -s "$SERVICE" \
    -S "$PARTITION_LIST" \
    -k "$UNLOCK_PASSWORD" \
    "$KEYCHAIN" >>"$LOG_FILE" 2>&1; then
    log "partition list re-applied for '$SERVICE'"
else
    log "failed to set partition list (see output above)"
    exit 1
fi
