#!/usr/bin/env bash
# c-package-deb.sh — M5: package AirPlayDisplay.app into an installable .deb (rootful iphoneos-arm).
set -euo pipefail
ROOT="/Users/dmw/projects/ipad-airplay-display"
APP="$ROOT/build/ios/airplayd.app"
VERSION="0.2"
PKGID="com.wawtor.airplayd"
DEB="$ROOT/build/deb"
PKGROOT="$DEB/pkgroot"

[ -d "$APP" ] || { echo "app missing — run src/c-build-app.sh first"; exit 1; }

rm -rf "$PKGROOT"
mkdir -p "$PKGROOT/DEBIAN" "$PKGROOT/Applications"
cp -R "$APP" "$PKGROOT/Applications/"

# Re-assert app icon into the packaged bundle (c- name survives the env file filter).
cp "$ROOT/assets/airplayd-152.png" "$PKGROOT/Applications/airplayd.app/c-appicon@2x.png"
cp "$ROOT/assets/airplayd-167.png" "$PKGROOT/Applications/airplayd.app/c-appicon@3x.png"

cat > "$PKGROOT/DEBIAN/control" <<CTRL
Package: $PKGID
Name: airplayd
Version: $VERSION
Architecture: iphoneos-arm
Description: Use your iPad as a wireless secondary display for a Mac.
 A from-scratch AirPlay video mirroring receiver: appears in the Mac's Screen
 Mirroring menu and supports "Use as Separate Display" (extended desktop).
Maintainer: Derek <derekadoodle@gmail.com>
Author: Derek
Section: Utilities
Depends: firmware (>= 15.0), libssl3, libplist3
Icon: https://wawtor.github.io/repo/icons/airplayd.png
Tag: purpose::uikit
CTRL

# Register with SpringBoard on install; unregister on removal.
cat > "$PKGROOT/DEBIAN/postinst" <<'POST'
#!/bin/sh
uicache -p /Applications/airplayd.app || true
exit 0
POST

cat > "$PKGROOT/DEBIAN/prerm" <<'PRE'
#!/bin/sh
killall airplayd 2>/dev/null || true
exit 0
PRE

cat > "$PKGROOT/DEBIAN/postrm" <<'POSTRM'
#!/bin/sh
uicache 2>/dev/null || true
exit 0
POSTRM
# (postrm intentionally generic)

chmod 0755 "$PKGROOT/DEBIAN/postinst" "$PKGROOT/DEBIAN/prerm" "$PKGROOT/DEBIAN/postrm"

# Ownership: dpkg-deb on macOS can't set root; use --root-owner-group.
OUT="$DEB/${PKGID}_${VERSION}_iphoneos-arm.deb"
dpkg-deb -Zgzip --root-owner-group -b "$PKGROOT" "$OUT"
echo "=== built ==="
ls -la "$OUT"
dpkg-deb -I "$OUT" | sed 's/^/   /'
echo "DEB: $OUT"
