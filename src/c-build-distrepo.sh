#!/usr/bin/env bash
# c-build-distrepo.sh — build a proper GPG-signed Debian *dist* repo (Wawtor Repo)
# into docs/ (GitHub Pages root). Supports multiple architectures + components.
set -euo pipefail
ROOT="/Users/dmw/projects/ipad-airplay-display"
REPO="$ROOT/docs"                 # Pages serves from /docs → repo base URL
export GNUPGHOME="$ROOT/.repo-keys"   # private key lives here; .gitignored, never pushed
ARCHES="iphoneos-arm iphoneos-arm64"
SUITE="stable"
COMP="main"
SIGNER="Wawtor Repo"

mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"

# 1. One-time signing key (no passphrase so signing is scriptable).
KEYID=$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^sec/{print $5; exit}' || true)
if [ -z "${KEYID:-}" ]; then
  echo "=== generating repo signing key ==="
  cat > "$GNUPGHOME/genkey.batch" <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Name-Real: $SIGNER
Name-Email: derekadoodle@gmail.com
Expire-Date: 0
%commit
EOF
  gpg --batch --gen-key "$GNUPGHOME/genkey.batch" 2>&1 | tail -2
  KEYID=$(gpg --list-secret-keys --with-colons | awk -F: '/^sec/{print $5; exit}')
fi
echo "signing key: $KEYID"

# 2. Reset the dist tree (preserve other docs like c-architecture.md).
rm -rf "$REPO/dists" "$REPO/pool"
rm -f "$REPO/Packages" "$REPO/Packages.gz" "$REPO/Packages.bz2" "$REPO/Release" \
      "$REPO/Release.gpg" "$REPO/InRelease" "$REPO/sileo-featured.json"
mkdir -p "$REPO/pool/$COMP"
cp "$ROOT/build/deb/"*.deb "$REPO/pool/$COMP/"

# 3. Per-architecture Packages indices.
cd "$REPO"
for arch in $ARCHES; do
  d="dists/$SUITE/$COMP/binary-$arch"
  mkdir -p "$d"
  dpkg-scanpackages --arch "$arch" "pool/$COMP" /dev/null > "$d/Packages" 2>/dev/null || true
  gzip -9c "$d/Packages" > "$d/Packages.gz"
  bzip2 -9c "$d/Packages" > "$d/Packages.bz2"
  echo "  $arch: $(grep -c '^Package:' "$d/Packages" || echo 0) package(s)"
done

# 4. dists/stable/Release with hashes of every Packages file (paths relative to here).
cd "$REPO/dists/$SUITE"
hashblock() {
  local algo="$1"; shift
  echo "$algo:"
  find "$COMP" -name 'Packages*' | sort | while read -r f; do
    local sum size
    sum=$("$@" "$f" | awk '{print $1}')
    size=$(wc -c < "$f" | tr -d ' ')
    printf ' %s %s %s\n' "$sum" "$size" "$f"
  done
}
{
  echo "Origin: Wawtor Repo"
  echo "Label: Wawtor Repo"
  echo "Suite: $SUITE"
  echo "Codename: $SUITE"
  echo "Version: 1.0"
  echo "Architectures: $ARCHES"
  echo "Components: $COMP"
  echo "Description: Derek's personal jailbreak repo — airplayd and friends."
  hashblock "MD5Sum" md5 -q
  hashblock "SHA256" shasum -a 256
} > Release

# 5. Sign: inline InRelease + detached Release.gpg.
gpg --batch --yes --clearsign -o InRelease Release
gpg --batch --yes -abs -o Release.gpg Release

# 6. Publish the public key (armored + binary keyring for apt trusted.gpg.d).
gpg --export --armor > "$REPO/wawtor.gpg"
gpg --export > "$REPO/wawtor-archive-keyring.gpg"

echo "=== dist repo tree ==="
find "$REPO/dists" "$REPO/pool" -type f | sed "s#$REPO/##"
echo "pubkey: docs/wawtor.gpg"
echo "REPO READY (signed): base = https://wawtor.github.io/repo/"
