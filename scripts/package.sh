#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "==> Building release..."
swift build -c release

# Determine the build output path
TRIPLE=$(swift build --show-destination 2>/dev/null | tr -d '\n')
if [ -z "$TRIPLE" ]; then
  TRIPLE="arm64-apple-macosx"
fi
EXE=".build/${TRIPLE}/release/App"

if [ ! -f "$EXE" ]; then
  echo "Error: Build output not found at $EXE"
  exit 1
fi

BUNDLE="DwarfStarLauncher.app"

echo "==> Assembling $BUNDLE..."
rm -rf "$BUNDLE"

mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$EXE" "$BUNDLE/Contents/MacOS/App"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/AppIcon/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"

chmod +x "$BUNDLE/Contents/MacOS/App"

echo "==> Done: $BUNDLE"
echo "    Contents/MacOS/App"
echo "    Contents/Info.plist"
echo "    Contents/Resources/AppIcon.icns"

# Optionally create DMG
if [ "$1" = "--dmg" ]; then
  echo ""
  if ! command -v create-dmg &> /dev/null; then
    if [ -f "/opt/homebrew/bin/create-dmg" ]; then
      export PATH="/opt/homebrew/bin:$PATH"
    elif [ -f "/usr/local/bin/create-dmg" ]; then
      export PATH="/usr/local/bin:$PATH"
    else
      echo "Error: create-dmg not found. Install it with:"
      echo "  brew install create-dmg"
      exit 1
    fi
  fi

  DMG="DwarfStarLauncher.dmg"
    echo "==> Creating $DMG..."
  rm -f "$DMG"
  create-dmg \
    --volname "DwarfStarLauncher" \
    --window-size 450 250 \
    --app-drop-link 340 160 \
    "$DMG" \
    "$BUNDLE"
  echo "==> Done: $DMG"
fi
