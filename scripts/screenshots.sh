#!/usr/bin/env bash
# Build the app and regenerate every screenshot variant with anonymous
# demo data (no real names/orgs/tokens).
#
# Outputs to:
#   docs/screenshots/      — App-Store marketing canvases (2880×1800)
#   website/assets/        — clean popup + settings cards for the website
#
# Usage:
#   scripts/screenshots.sh
set -euo pipefail

cd "$(dirname "$0")/.."

./build.sh

# App Store marketing canvases (full 2880×1800 with headline column)
mkdir -p docs/screenshots
.build/release/ClaudeStatus --screenshot enterprise docs/screenshots
.build/release/ClaudeStatus --screenshot pro        docs/screenshots

# Website assets (transparent popup + settings cards)
mkdir -p website/assets
.build/release/ClaudeStatus --screenshot popup-enterprise website/assets
.build/release/ClaudeStatus --screenshot popup-pro        website/assets
.build/release/ClaudeStatus --screenshot settings         website/assets
.build/release/ClaudeStatus --screenshot diagnostics      website/assets

echo
echo "✓ Marketing screenshots:"
ls -lh docs/screenshots/*.png | awk '{print "  ", $9, $5}'
echo
echo "✓ Website assets:"
ls -lh website/assets/*.png | awk '{print "  ", $9, $5}'
