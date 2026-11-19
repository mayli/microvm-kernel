#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_src
require_cmd make
require_file "$CONFIG_UPSTREAM/microvm-kernel-ci-x86_64-6.18.config"
require_file "$CONFIG_UPSTREAM/ci.config"
require_file "$CONFIG_UPSTREAM/efi.config"

cd "$SRC"

log "seeding .config from the Firecracker base config"
cp "$CONFIG_UPSTREAM/microvm-kernel-ci-x86_64-6.18.config" .config

log "merging upstream fragments and project overrides"
sh scripts/kconfig/merge_config.sh -m .config \
    "$CONFIG_UPSTREAM/ci.config" \
    "$CONFIG_UPSTREAM/efi.config" \
    "$CONFIG_FRAGMENTS"/*.config

log "resolving Kconfig dependencies for the Ubuntu 7.0 tree"
make olddefconfig

"$ROOT/scripts/verify-config.sh" "$SRC/.config"

mkdir -p "$OUT"
cp .config "$OUT/microvm.config"
log "rendered config: $OUT/microvm.config"

log "importing config into debian.master/config/annotations for amd64-microvm"
debian/scripts/misc/annotations \
    --arch amd64 --flavour microvm --import .config

# The Ubuntu packaging builds out-of-tree and refuses a dirty source tree.
# olddefconfig above writes in-tree artifacts, so clean them now.  The
# generated config remains available in $OUT/microvm.config.
log "cleaning in-tree Kconfig artifacts"
make mrproper

log "config imported"
