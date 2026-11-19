#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_src
require_cmd fakeroot
require_cmd dpkg-buildpackage

UPSTREAM="${UPSTREAM:-7.0.0}"
UBUNTU_SOURCE_VERSION="${UBUNTU_SOURCE_VERSION:-7.0.0-43.43}"
ORIG="$WORK/linux_${UPSTREAM}.orig.tar.gz"

if [[ ! -f "$ORIG" ]]; then
    require_cmd curl
    log "downloading $ORIG (about 255 MiB)"
    tmp="$ORIG.part"
    curl -fL --retry 3 -o "$tmp" \
        "https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/linux/${UBUNTU_SOURCE_VERSION}/linux_${UPSTREAM}.orig.tar.gz"
    mv "$tmp" "$ORIG"
else
    log "using existing orig tarball: $ORIG"
fi

cd "$SRC"

log "regenerating debian/changelog"
fakeroot debian/rules clean

log "building source package (format 1.0, includes orig tarball)"
dpkg-buildpackage -S -sa -us -uc

changes="$(find "$WORK" -maxdepth 1 -type f -name 'linux_*_source.changes' \
    -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2- || true)"

[[ -n "$changes" ]] || die "no source .changes file was produced"
log "source package: $changes"
