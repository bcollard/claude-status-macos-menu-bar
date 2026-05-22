#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Claude Status"
EXEC_NAME="ClaudeStatus"
BUILD_CONFIG="release"

cd "$(dirname "$0")"

echo "→ swift build -c $BUILD_CONFIG"
swift build -c "$BUILD_CONFIG"

BIN_DIR=$(swift build -c "$BUILD_CONFIG" --show-bin-path)
EXEC_PATH="$BIN_DIR/$EXEC_NAME"

if [[ ! -x "$EXEC_PATH" ]]; then
  echo "✗ Binary not found at $EXEC_PATH" >&2
  exit 1
fi

APP_DIR=".build/${APP_NAME}.app"
echo "→ Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXEC_PATH" "$APP_DIR/Contents/MacOS/$EXEC_NAME"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

echo "→ Ad-hoc codesign"
codesign --force --deep --sign - "$APP_DIR"

echo
echo "✓ Built: $APP_DIR"
echo "  Open: open \"$APP_DIR\""
echo "  Install: cp -R \"$APP_DIR\" /Applications/"
