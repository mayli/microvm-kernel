#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_src
require_file "$SRC/.config"
require_cmd fakeroot
require_cmd dpkg-deb

cd "$SRC"

log "cleaning the source tree"
fakeroot debian/rules clean

log "building the microvm flavour"
DEB_BUILD_OPTIONS="parallel=$(nproc)" fakeroot debian/rules binary-microvm

mkdir -p "$OUT/debs"
find "$WORK" -maxdepth 1 -type f -name 'linux-*microvm*.deb' \
    -exec cp -v {} "$OUT/debs/" \;

deb="$(find "$OUT/debs" -maxdepth 1 -type f -name 'linux-image-*microvm*.deb' | head -n 1 || true)"
if [[ -n "$deb" ]]; then
    rm -rf "$OUT/root"
    mkdir -p "$OUT/root"
    dpkg-deb -x "$deb" "$OUT/root"
    find "$OUT/root" -type f -name 'vmlinuz*' -exec cp -v {} "$OUT/" \;
fi

log "build artifacts"
ls -lh "$OUT/debs"
if compgen -G "$OUT/vmlinuz*" >/dev/null; then
    ls -lh "$OUT"/vmlinuz*
fi
