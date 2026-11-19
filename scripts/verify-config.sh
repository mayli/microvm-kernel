#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

cfg="${1:-$SRC/.config}"
require_file "$cfg"

fail=0

if grep -q '=m$' "$cfg"; then
    printf 'FAIL: these options are still modules:\n' >&2
    grep '=m$' "$cfg" | head -n 20 >&2
    fail=1
fi

required_y=(
    CONFIG_VIRTIO_PCI
    CONFIG_VIRTIO_BLK
    CONFIG_VIRTIO_NET
    CONFIG_VIRTIO_CONSOLE
    CONFIG_EXT4_FS
    CONFIG_SQUASHFS
    CONFIG_BLK_DEV_LOOP
    CONFIG_OVERLAY_FS
    CONFIG_DEVTMPFS
    CONFIG_EFI_PARTITION
    CONFIG_NF_TABLES
    CONFIG_NF_TABLES_INET
    CONFIG_NETFILTER_XT_MATCH_STATE
    CONFIG_SECURITY_APPARMOR
)

for sym in "${required_y[@]}"; do
    if ! grep -qx "$sym=y" "$cfg"; then
        printf 'FAIL: %s is not =y\n' "$sym" >&2
        fail=1
    fi
done

for sym in CONFIG_MODULES CONFIG_DEVMEM; do
    if ! grep -qx "# $sym is not set" "$cfg"; then
        printf 'FAIL: %s should be disabled\n' "$sym" >&2
        fail=1
    fi
done

if (( fail )); then
    exit 1
fi

printf 'config verification passed: %s\n' "$cfg"
