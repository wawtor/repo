#!/usr/bin/env bash
# c-package-deb.sh — M5: package AirPlayDisplay.app into an installable .deb (rootful iphoneos-arm).
set -euo pipefail
ROOT="/Users/dmw/projects/ipad-airplay-display"
APP="$ROOT/build/ios/AirPlayDisplay.app"
VERSION="0.1"
PKGID="com.wawtor.airplaydisplay"
DEB="$ROOT/build/deb"
PKGROOT="$DEB/pkgroot"

[ -d "$APP" ] || { echo "app missing — run src/c-build-app.sh first"; exit 1; }

rm -rf "$PKGROOT"
mkdir -p "$PKGROOT/DEBIAN" "$PKGROOT/Applications"
cp -R "$APP" "$PKGROOT/Applications/"

cat > "$PKGROOT/DEBIAN/control" <<CTRL
Package: $PKGID
Name: AirPlay Display
Version: $VERSION
Architecture: iphoneos-arm
Description: Use your iPad as a wireless secondary display for a Mac.
 A from-scratch AirPlay video mirroring receiver: appears in the Mac's Screen
 Mirroring menu and supports "Use as Separate Display" (extended desktop).
Maintainer: Derek <derekadoodle@gmail.com>
Author: Derek
Section: Utilities
Depends: firmware (>= 15.0), libssl3, libplist3
Tag: purpose::uikit
CTRL

# Register with SpringBoard on install; unregister on removal.
cat > "$PKGROOT/DEBIAN/postinst" <<'POST'
#!/bin/sh
uicache -p /Applications/AirPlayDisplay.app || true
exit 0
POST

cat > "$PKGROOT/DEBIAN/prerm" <<'PRE'
#!/bin/sh
killall AirPlayDisplay 2>/dev/null || true
exit 0
PRE

cat > "$PKGROOT/DEBIAN/postrm" <<'POSTRM'
#!/bin/sh
uicache 2>/dev/null || true
exit 0
POSTRM

chmod 0755 "$PKGROOT/DEBIAN/postinst" "$PKGROOT/DEBIAN/prerm" "$PKGROOT/DEBIAN/postrm"

# Ownership: dpkg-deb on macOS can't set root; use --root-owner-group.
OUT="$DEB/${PKGID}_${VERSION}_iphoneos-arm.deb"
dpkg-deb -Zgzip --root-owner-group -b "$PKGROOT" "$OUT"
echo "=== built ==="
ls -la "$OUT"
dpkg-deb -I "$OUT" | sed 's/^/   /'
echo "DEB: $OUT"
