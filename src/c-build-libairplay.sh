#!/usr/bin/env bash
# c-build-libairplay.sh — M3: cross-compile UxPlay's lib/ core into libairplay.a for iOS arm64.
# Strips the GStreamer renderer; keeps RAOP server + FairPlay auth + native Bonjour dns_sd + llhttp.
set -euo pipefail
ROOT="/Users/dmw/projects/ipad-airplay-display"
source "$ROOT/scratch/c-env.sh"

LIB="$ROOT/vendor/UxPlay/lib"
DEPS="$ROOT/vendor/ios-deps/usr"
OUT="$ROOT/build/ios"
OBJ="$OUT/obj"
mkdir -p "$OBJ"

# Source set (mirrors the CMake aux_source_directory globs for the Apple/native-dns_sd path)
SRCS=()
for f in "$LIB"/*.c;            do SRCS+=("$f"); done
for f in "$LIB"/playfair/*.c;   do SRCS+=("$f"); done
for f in "$LIB"/llhttp/*.c;     do SRCS+=("$f"); done
SRCS+=("$LIB/dns_sd/dns_sd.c")

INCS=( -I"$LIB" -I"$LIB/playfair" -I"$LIB/llhttp" -I"$LIB/dns_sd" -I"$DEPS/include" )
DEFS=( -DNOHOLD -DPLIST_210 )
CFLAGS=( -arch arm64 -isysroot "$THEOS_SDK" -mios-version-min="$IOS_DEPLOY_TARGET" \
         -O2 -fPIC -Wall -Wno-unused-function -Wno-deprecated-declarations )

echo "=== compiling ${#SRCS[@]} source files for iOS arm64 ==="
OBJS=()
fail=0
for src in "${SRCS[@]}"; do
  o="$OBJ/$(basename "${src%.c}").o"
  if xcrun -sdk macosx clang "${CFLAGS[@]}" "${DEFS[@]}" "${INCS[@]}" -c "$src" -o "$o" 2> "$o.log"; then
    OBJS+=("$o")
  else
    echo "  FAIL: $(basename "$src")"; sed 's/^/      /' "$o.log" | head -12; fail=1
  fi
done

if [ "$fail" -ne 0 ]; then echo "=== compile errors above ==="; exit 1; fi

echo "=== archiving libairplay.a ==="
rm -f "$OUT/libairplay.a"
xcrun -sdk macosx ar rcs "$OUT/libairplay.a" "${OBJS[@]}"
echo "=== result ==="
ls -la "$OUT/libairplay.a"
xcrun -sdk macosx nm "$OUT/libairplay.a" 2>/dev/null | grep -E " T _raop_init$| T _dnssd_init$| T _raop_start_httpd$" | head
echo "SYMBOLS above confirm the public API is present."
