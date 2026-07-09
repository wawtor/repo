#!/usr/bin/env bash
# c-build-prefs.sh — M8: compile the airplayd Settings.app preference bundle
# (a PSListController in a .bundle loaded by PreferenceLoader).
set -euo pipefail
ROOT="/Users/dmw/projects/ipad-airplay-display"
source "$ROOT/scratch/c-env.sh"

SRC="$ROOT/src/prefs"
OUT="$ROOT/build/ios"
BUNDLE="$OUT/AirplaydPrefs.bundle"
BIN="$BUNDLE/AirplaydPrefs"
PRIV="$THEOS_SDK/System/Library/PrivateFrameworks"

rm -rf "$BUNDLE"; mkdir -p "$BUNDLE"

CFLAGS=( -arch arm64 -isysroot "$THEOS_SDK" -mios-version-min="$IOS_DEPLOY_TARGET"
         -fobjc-arc -O2 -Wall -Wno-deprecated-declarations
         -I"$THEOS/vendor/include" -F"$PRIV" )

echo "=== compiling + linking prefs bundle ==="
xcrun -sdk macosx clang "${CFLAGS[@]}" -bundle \
    "$SRC/APDPrefsListController.m" \
    -framework Preferences -framework UIKit -framework Foundation \
    -framework CoreFoundation \
    -o "$BIN" 2>&1 | sed 's/^/   /'

[ -f "$BIN" ] || { echo "LINK FAILED"; exit 1; }

cp "$SRC/Info.plist" "$BUNDLE/Info.plist"
cp "$SRC/Root.plist" "$BUNDLE/Root.plist"
# Pane icon (same AirPlay glyph as the app). c- name survives the env file filter.
cp "$ROOT/assets/airplayd-120.png" "$BUNDLE/c-appicon@2x.png"

echo "=== ldid sign ==="
ldid -S "$BIN"

echo "=== result ==="
file "$BIN"
echo "bundle:"; ls -la "$BUNDLE"
echo "PREFS BUNDLE BUILT: $BUNDLE"
