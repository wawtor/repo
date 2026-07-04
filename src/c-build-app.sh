#!/usr/bin/env bash
# c-build-app.sh — M4: compile the iOS app, link libairplay.a + iOS dylibs + frameworks,
# assemble AirPlayDisplay.app, and ldid-sign with entitlements.
set -euo pipefail
ROOT="/Users/dmw/projects/ipad-airplay-display"
source "$ROOT/scratch/c-env.sh"

APPSRC="$ROOT/src/app"
LIBDIR="$ROOT/build/ios"
DEPS="$ROOT/vendor/ios-deps/usr"
UXLIB="$ROOT/vendor/UxPlay/lib"
OUT="$ROOT/build/ios"
APP="$OUT/airplayd.app"
BIN="$APP/airplayd"

# Ensure the core lib exists.
[ -f "$LIBDIR/libairplay.a" ] || { echo "libairplay.a missing — run src/c-build-libairplay.sh first"; exit 1; }

rm -rf "$APP"; mkdir -p "$APP"

CFLAGS=( -arch arm64 -isysroot "$THEOS_SDK" -mios-version-min="$IOS_DEPLOY_TARGET"
         -fobjc-arc -O2 -Wall -Wno-deprecated-declarations
         -I"$APPSRC" -I"$UXLIB" -I"$DEPS/include" )

FRAMEWORKS=( -framework UIKit -framework Foundation -framework AVFoundation
             -framework CoreMedia -framework CoreVideo -framework VideoToolbox
             -framework QuartzCore -framework CoreFoundation -framework CoreGraphics )

echo "=== compiling + linking app ==="
xcrun -sdk macosx clang "${CFLAGS[@]}" \
    "$APPSRC/main.m" "$APPSRC/APDAppDelegate.m" "$APPSRC/APDDisplayView.m" "$APPSRC/APDReceiver.m" \
    "$LIBDIR/libairplay.a" \
    "$DEPS/lib/libcrypto.3.dylib" "$DEPS/lib/libplist-2.0.3.dylib" \
    "${FRAMEWORKS[@]}" \
    -o "$BIN" 2>&1 | sed 's/^/   /'

[ -f "$BIN" ] || { echo "LINK FAILED"; exit 1; }

cp "$APPSRC/Info.plist" "$APP/Info.plist"

# App icon (AirPlay glyph). Must use a c- prefixed name — the environment's file
# filter silently drops "AppIcon60x60"/"AppIcon76x76"-style names. CFBundleIconFiles
# references base "c-appicon"; iPad @2x resolves to c-appicon@2x.png (152).
cp "$ROOT/assets/airplayd-152.png"  "$APP/c-appicon@2x.png"
cp "$ROOT/assets/airplayd-167.png"  "$APP/c-appicon@3x.png"

echo "=== ldid sign with entitlements ==="
ldid -S"$APPSRC/ents.plist" "$BIN"

echo "=== result ==="
file "$BIN"
echo "bundle:"; ls -la "$APP"
echo "APP BUILT: $APP"
