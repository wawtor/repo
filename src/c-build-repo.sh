#!/usr/bin/env bash
# c-build-repo.sh — M6: assemble a Sileo/APT repo hosting the AirPlay Display .deb.
# Output: build/repo/ (static files — serve over HTTP or push to GitHub Pages).
set -euo pipefail
ROOT="/Users/dmw/projects/ipad-airplay-display"
DEB=$(ls -t "$ROOT/build/deb/"*.deb | head -1)
REPO="$ROOT/build/repo"

[ -f "$DEB" ] || { echo "no .deb — run src/c-package-deb.sh first"; exit 1; }

rm -rf "$REPO"; mkdir -p "$REPO/debs"
cp "$DEB" "$REPO/debs/"

cd "$REPO"
# Packages index (paths relative to repo root).
dpkg-scanpackages -m debs /dev/null > Packages 2>/dev/null
gzip -9c Packages > Packages.gz
if command -v bzip2 >/dev/null; then bzip2 -9c Packages > Packages.bz2; fi

# Release file with hashes of the Packages files.
gen_hashes() {
  local algo="$1" prog="$2"
  echo "${algo}:"
  for f in Packages Packages.gz Packages.bz2; do
    [ -f "$f" ] || continue
    local sum size
    sum=$($prog "$f" | awk '{print $1}')
    size=$(wc -c < "$f" | tr -d ' ')
    printf ' %s %s %s\n' "$sum" "$size" "$f"
  done
}

cat > Release <<REL
Origin: Wawtor Repo
Label: Wawtor Repo
Suite: stable
Version: 1.0
Codename: wawtor
Architectures: iphoneos-arm
Components: main
Description: Derek's personal jailbreak repo — AirPlay Display and friends.
REL
{
  gen_hashes "MD5Sum" "md5"
  gen_hashes "SHA1" "shasum -a 1"
  gen_hashes "SHA256" "shasum -a 256"
} >> Release

# Sileo presentation niceties.
cat > sileo-featured.json <<'JSON'
{ "class": "FeaturedBannersView", "banners": [] }
JSON

echo "=== repo tree ==="
ls -la "$REPO"
echo "=== Packages ==="
cat "$REPO/Packages"
echo "REPO READY: $REPO"
