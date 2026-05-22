#!/usr/bin/env bash
# Builds a .app, zips it for distribution, prints the SHA-256 to paste
# into the Homebrew cask formula.
#
# Usage:
#   scripts/release.sh 0.1.0
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>   e.g. $0 0.1.0" >&2
  exit 1
fi

cd "$(dirname "$0")/.."
./build.sh

OUT_DIR=".build/release"
APP=".build/Claude Status.app"
ZIP="$OUT_DIR/ClaudeStatus-$VERSION.zip"

mkdir -p "$OUT_DIR"
rm -f "$ZIP"

# Use ditto so xattrs survive (vs `zip`, which corrupts the signed bundle).
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
if stat -f%z "$ZIP" >/dev/null 2>&1; then
  SIZE=$(stat -f%z "$ZIP")          # macOS / BSD
else
  SIZE=$(stat -c%s "$ZIP")          # GNU coreutils
fi

echo
echo "✓ $ZIP  ($SIZE bytes)"
echo "  sha256: $SHA"
echo
echo "Next:"
echo "  1. Create GitHub release tag v$VERSION and upload the zip."
echo "  2. Update Casks/claude-status.rb:"
echo "       version \"$VERSION\""
echo "       sha256 \"$SHA\""
echo "  3. Push the cask file to your homebrew tap repo."
