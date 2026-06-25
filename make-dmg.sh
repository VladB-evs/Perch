#!/bin/bash
#
# make-dmg.sh — Build a Release Perch.app and package it into a styled,
# drag-to-install DMG (custom white background + arranged icons).
#
# Usage:  ./make-dmg.sh
# Output: Perch.dmg in the project root.
#
# Uses your project's automatic code signing, which is enough to run on *your
# own* Mac. To share with others the app must be Developer ID signed + notarized
# (see notes at the bottom).

set -euo pipefail

PROJECT="Perch.xcodeproj"
SCHEME="Perch"
CONFIG="Release"
APP_NAME="Perch"
VOL="Perch"
DMG_NAME="${APP_NAME}.dmg"

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

BUILD_DIR="$ROOT/.build-dmg"
APP_PATH="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME.app"
RW_DMG="$ROOT/.rw.dmg"
BG_PNG="$ROOT/.dmg-background.png"

cleanup() { rm -rf "$BUILD_DIR" "$RW_DMG" "$BG_PNG"; }
trap cleanup EXIT

# ── 1. Background image ───────────────────────────────────────────────────────
echo "▸ Rendering installer background…"
swift "$ROOT/dmg/make-background.swift" "$BG_PNG" >/dev/null

# ── 2. Build the app ──────────────────────────────────────────────────────────
echo "▸ Building $APP_NAME ($CONFIG)…"
rm -rf "$BUILD_DIR"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
  -derivedDataPath "$BUILD_DIR" -allowProvisioningUpdates build >/dev/null
[ -d "$APP_PATH" ] || { echo "✗ Build failed: $APP_PATH not found"; exit 1; }

# ── 3. Create a writable image and fill it ────────────────────────────────────
echo "▸ Preparing disk image…"
# Detach any stale copy of the volume first.
[ -d "/Volumes/$VOL" ] && hdiutil detach "/Volumes/$VOL" -force >/dev/null 2>&1 || true
rm -f "$RW_DMG"
hdiutil create -volname "$VOL" -fs HFS+ -size 64m -ov "$RW_DMG" >/dev/null
hdiutil attach "$RW_DMG" -nobrowse -noautoopen >/dev/null
MNT="/Volumes/$VOL"

cp -R "$APP_PATH" "$MNT/"
ln -s /Applications "$MNT/Applications"
mkdir "$MNT/.background"
cp "$BG_PNG" "$MNT/.background/background.png"

# ── 4. Style the Finder window (background + icon positions) ───────────────────
echo "▸ Styling Finder window…"
STYLED=1
osascript <<EOF || STYLED=0
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {300, 200, 940, 640}
    set vo to the icon view options of container window
    set arrangement of vo to not arranged
    set icon size of vo to 128
    set text size of vo to 12
    set background picture of vo to file ".background:background.png"
    set position of item "$APP_NAME.app" of container window to {180, 200}
    set position of item "Applications" of container window to {460, 200}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
[ "$STYLED" = 1 ] || echo "  ⚠︎ Finder styling was skipped (needs an interactive session / Automation permission). The DMG will still work, just unstyled."

# ── 5. Finalize: detach and compress ──────────────────────────────────────────
echo "▸ Compressing…"
sync
for _ in 1 2 3 4 5; do hdiutil detach "$MNT" >/dev/null 2>&1 && break || sleep 1; done
rm -f "$ROOT/$DMG_NAME"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$ROOT/$DMG_NAME" >/dev/null

echo "✓ Done → $ROOT/$DMG_NAME"

# ── Sharing with other Macs (optional) ───────────────────────────────────────
# 1. Sign Release with a "Developer ID Application" certificate (paid account).
# 2. Notarize and staple the finished DMG:
#      xcrun notarytool submit Perch.dmg \
#        --apple-id "you@example.com" --team-id 2NS6MGWC82 \
#        --password "<app-specific-password>" --wait
#      xcrun stapler staple Perch.dmg
