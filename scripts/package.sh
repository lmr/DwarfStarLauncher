#!/bin/bash
set -e

# Packaging script for DwarfStarLauncher.
# Produces DwarfStarLauncher.app; optionally a DMG with --dmg.
# The bundle is ad-hoc signed for local execution. Distribution
# notarization is out of scope and must be handled separately.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "==> Building release..."
# Default build system on Xcode 16+ / macOS 27 is swiftbuild.
# Do NOT pass --build-system native (deprecated): it writes to a different
# output dir (.build/<triple>/release) than swiftbuild
# (.build/out/Products/Release), which diverges from `swift run`/`swift build`.
swift build -c release

# Resolve the binary path from the active build system.
BIN_DIR="$(swift build -c release --show-bin-path 2>/dev/null | tr -d '\n')"
EXE="${BIN_DIR}/App"

if [ ! -f "$EXE" ]; then
  # Fallback for older toolchains without --show-bin-path.
  TRIPLE=$(swift build --show-destination 2>/dev/null | tr -d '\n')
  if [ -z "$TRIPLE" ]; then
    TRIPLE="arm64-apple-macosx"
  fi
  EXE=".build/${TRIPLE}/release/App"
fi

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

codesign --force --sign - --options runtime "$BUNDLE" || echo "codesign skipped"

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
