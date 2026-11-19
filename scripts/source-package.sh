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

source_upload="${SOURCE_UPLOAD:-sa}"
case "$source_upload" in
    sa|sd) ;;
    *) die "SOURCE_UPLOAD must be 'sa' (include orig) or 'sd' (omit orig)" ;;
esac

log "building source package (format 1.0, source upload: $source_upload)"
dpkg-buildpackage -S "-${source_upload}" -us -uc

changes="$(find "$WORK" -maxdepth 1 -type f -name 'linux_*_source.changes' \
    -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2- || true)"

[[ -n "$changes" ]] || die "no source .changes file was produced"
log "source package: $changes"
