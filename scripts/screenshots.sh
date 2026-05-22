#!/usr/bin/env bash
# Build the app and regenerate App-Store-ready screenshots with anonymous
# demo data (no real names/orgs/tokens). Writes to docs/screenshots/.
#
# Usage:
#   scripts/screenshots.sh [outDir]   # default: docs/screenshots
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="${1:-docs/screenshots}"

./build.sh

mkdir -p "$OUT"

.build/release/ClaudeStatus --screenshot enterprise "$OUT"
.build/release/ClaudeStatus --screenshot pro        "$OUT"

echo
echo "✓ Screenshots written to $OUT/"
ls -lh "$OUT/" | tail -n +2
