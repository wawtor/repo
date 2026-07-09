#!/usr/bin/env bash
# c-package-deb.sh — M5: package AirPlayDisplay.app into an installable .deb (rootful iphoneos-arm).
set -euo pipefail
ROOT="/Users/dmw/projects/ipad-airplay-display"
APP="$ROOT/build/ios/airplayd.app"
VERSION="0.3"
PKGID="com.wawtor.airplayd"
DEB="$ROOT/build/deb"
PKGROOT="$DEB/pkgroot"

[ -d "$APP" ] || { echo "app missing — run src/c-build-app.sh first"; exit 1; }

PREFSBUNDLE="$ROOT/build/ios/AirplaydPrefs.bundle"
[ -d "$PREFSBUNDLE" ] || { echo "prefs bundle missing — run src/c-build-prefs.sh first"; exit 1; }

rm -rf "$PKGROOT"
mkdir -p "$PKGROOT/DEBIAN" "$PKGROOT/Applications" \
         "$PKGROOT/Library/LaunchDaemons" "$PKGROOT/usr/local/bin" \
         "$PKGROOT/Library/PreferenceBundles" "$PKGROOT/Library/PreferenceLoader/Preferences"
cp -R "$APP" "$PKGROOT/Applications/"

# Re-assert app icon into the packaged bundle (c- name survives the env file filter).
cp "$ROOT/assets/airplayd-152.png" "$PKGROOT/Applications/airplayd.app/c-appicon@2x.png"
cp "$ROOT/assets/airplayd-167.png" "$PKGROOT/Applications/airplayd.app/c-appicon@3x.png"

# Boot auto-start: LaunchDaemon + its launcher script (starts airplayd in the
# background after every reboot so the receiver is always discoverable).
cp "$ROOT/assets/boot/com.wawtor.airplayd.boot.plist" "$PKGROOT/Library/LaunchDaemons/"
cp "$ROOT/assets/boot/c-airplayd-boot.sh" "$PKGROOT/usr/local/bin/c-airplayd-boot.sh"
chmod 0755 "$PKGROOT/usr/local/bin/c-airplayd-boot.sh"

# Settings.app preference pane: PreferenceBundle + PreferenceLoader entry.
cp -R "$PREFSBUNDLE" "$PKGROOT/Library/PreferenceBundles/"
cp "$ROOT/src/prefs/entry.plist" "$PKGROOT/Library/PreferenceLoader/Preferences/airplayd.plist"

# control is written per-architecture in the packaging loop below.
write_control() {
  local arch="$1"
  cat > "$PKGROOT/DEBIAN/control" <<CTRL
Package: $PKGID
Name: airplayd
Version: $VERSION
Architecture: $arch
Description: Use your iPad as a wireless secondary display for a Mac.
 A from-scratch AirPlay video mirroring receiver: appears in the Mac's Screen
 Mirroring menu and supports "Use as Separate Display" (extended desktop).
Maintainer: Derek <derekadoodle@gmail.com>
Author: Derek
Section: Utilities
Depends: firmware (>= 15.0), libssl3, libplist3, preferenceloader
Icon: https://wawtor.github.io/repo/icons/airplayd.png
Tag: purpose::uikit
CTRL
}

# Register with SpringBoard and load the boot daemon on install.
cat > "$PKGROOT/DEBIAN/postinst" <<'POST'
#!/bin/sh
uicache -p /Applications/airplayd.app || true
# Load the boot LaunchDaemon now so it also survives without waiting for a reboot.
launchctl load -w /Library/LaunchDaemons/com.wawtor.airplayd.boot.plist 2>/dev/null || true
exit 0
POST

cat > "$PKGROOT/DEBIAN/prerm" <<'PRE'
#!/bin/sh
launchctl unload -w /Library/LaunchDaemons/com.wawtor.airplayd.boot.plist 2>/dev/null || true
killall airplayd 2>/dev/null || true
exit 0
PRE

cat > "$PKGROOT/DEBIAN/postrm" <<'POSTRM'
#!/bin/sh
rm -f /var/mobile/.apd-boot /var/mobile/apd-boot.log 2>/dev/null || true
uicache 2>/dev/null || true
exit 0
POSTRM
# (postrm intentionally generic)

chmod 0755 "$PKGROOT/DEBIAN/postinst" "$PKGROOT/DEBIAN/prerm" "$PKGROOT/DEBIAN/postrm"

# The payload is the same arm64 Mach-O either way; emit one deb per dpkg architecture
# so the repo installs on both iphoneos-arm and iphoneos-arm64 bootstraps.
# Ownership: dpkg-deb on macOS can't set root; use --root-owner-group.
for arch in iphoneos-arm iphoneos-arm64; do
  write_control "$arch"
  OUT="$DEB/${PKGID}_${VERSION}_${arch}.deb"
  dpkg-deb -Zgzip --root-owner-group -b "$PKGROOT" "$OUT"
  echo "=== built ($arch) ==="
  ls -la "$OUT"
done
echo "DEBs in $DEB:"; ls -1 "$DEB"/*.deb
