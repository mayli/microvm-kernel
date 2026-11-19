#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

KERNEL="${1:-$(find "$OUT" -maxdepth 1 -type f -name 'vmlinuz-*microvm' -print -quit)}"
[[ -n "$KERNEL" ]] || die "no vmlinuz-*microvm found in $OUT; run 'make build' first"
require_file "$KERNEL"

require_cmd qemu-system-x86_64
require_cmd busybox
require_cmd cpio
require_cmd gzip
require_cmd mksquashfs
require_cmd mkfs.ext4
require_cmd debugfs
require_cmd parted
require_cmd dd

TEST="$OUT/boot-test"
rm -rf "$TEST"
mkdir -p "$TEST/rootfs" "$TEST/squash"

cat > "$TEST/init" <<'EOF'
#!/bin/sh
set -x
mkdir -p /proc /sys /dev /mnt
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev 2>/dev/null || true

# devtmpfs may not create loop nodes in the initramfs.
[ -e /dev/loop-control ] || mknod /dev/loop-control c 10 237 2>/dev/null || true
for i in 0 1 2 3; do
    [ -e /dev/loop$i ] || mknod /dev/loop$i b 7 $i 2>/dev/null || true
done

echo "UNAME: $(uname -r)"
echo "CMDLINE: $(cat /proc/cmdline)"
echo "VERSION: $(cat /proc/version)"
if [ -f /proc/modules ]; then
    echo "MODULES: $(wc -l < /proc/modules)"
else
    echo "MODULES: 0"
fi

if [ -f /proc/config.gz ]; then
    echo "CONFIG_GZIP: yes"
    zcat /proc/config.gz | grep -E '^(CONFIG_MODULES=|CONFIG_DEVMEM=|CONFIG_EFI_PARTITION=|CONFIG_VIRTIO_BLK=|CONFIG_SQUASHFS=|CONFIG_BLK_DEV_LOOP=|CONFIG_OVERLAY_FS=|CONFIG_NF_TABLES_INET=|CONFIG_SECURITY_APPARMOR=|CONFIG_DAMON=)' || true
else
    echo "CONFIG_GZIP: no"
fi

if [ -b /dev/vda1 ]; then
    mkdir -p /mnt/disk
    if mount -t ext4 /dev/vda1 /mnt/disk; then
        echo "DISK_MOUNT: ok"
        echo "DISK_HELLO: $(cat /mnt/disk/hello)"
    else
        echo "DISK_MOUNT: failed"
    fi
else
    echo "DISK_MOUNT: no /dev/vda1"
    ls -l /dev/vd* 2>/dev/null || true
fi

mkdir -p /mnt/lower /mnt/upper /mnt/work /mnt/merged
if [ -f /mnt/disk/test.squashfs ]; then
    if losetup /dev/loop0 /mnt/disk/test.squashfs &&
       mount -t squashfs /dev/loop0 /mnt/lower; then
        echo "SQUASHFS: ok"
        echo "SQUASHFS_HELLO: $(cat /mnt/lower/hello)"
    else
        echo "SQUASHFS: failed"
    fi
    if mount -t overlay overlay \
        -o lowerdir=/mnt/lower,upperdir=/mnt/upper,workdir=/mnt/work \
        /mnt/merged; then
        echo "OVERLAY: ok"
        echo "OVERLAY_HELLO: $(cat /mnt/merged/hello)"
        echo "persistent" > /mnt/merged/newfile
        echo "OVERLAY_WRITE: ok"
    else
        echo "OVERLAY: failed"
    fi
else
    echo "SQUASHFS: no image"
fi

if [ -d /sys/class/net/eth0 ]; then
    echo "NET: eth0"
else
    echo "NET: none"
    ls /sys/class/net
fi

mkdir -p /run
if [ -x /usr/sbin/nft ] &&
   /usr/sbin/nft add table inet test &&
   /usr/sbin/nft add chain inet test input \
       '{ type filter hook input priority 0; policy accept; }' &&
   /usr/sbin/nft add rule inet test input tcp dport 22 accept; then
    echo "NFT: ok"
else
    echo "NFT: failed"
fi

echo "BOOT_OK"
sync
poweroff -f
EOF
chmod +x "$TEST/init"

mkdir -p "$TEST/rootfs"/{bin,sbin,proc,sys,dev,mnt,run,tmp}
BUSYBOX="$(command -v busybox)"
require_file "$BUSYBOX"
cp "$BUSYBOX" "$TEST/rootfs/bin/busybox"
for app in sh mount umount mkdir cat echo sleep poweroff zcat grep wc ls ln sync dmesg cut awk find test printf mknod losetup; do
    ln -sf /bin/busybox "$TEST/rootfs/bin/$app"
done

copy_with_libs() {
    local bin="$1"
    install -D -m755 "$bin" "$TEST/rootfs$bin"
    ldd "$bin" | awk '{for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i}' | while read -r lib; do
        install -D -m755 "$lib" "$TEST/rootfs$lib"
    done
}
copy_with_libs /usr/sbin/nft

cp "$TEST/init" "$TEST/rootfs/init"
chmod +x "$TEST/rootfs/init"
( cd "$TEST/rootfs" && find . -print0 | cpio --null -o --format=newc 2>/dev/null | gzip -9 ) \
    > "$TEST/initramfs.cpio.gz"

echo "hello from ext4" > "$TEST/hello"
echo "hello from squashfs" > "$TEST/squash/hello"
mksquashfs "$TEST/squash" "$TEST/squash.img" -noappend -quiet

truncate -s 62M "$TEST/part.img"
mkfs.ext4 -F -q "$TEST/part.img"
debugfs -w -R "write $TEST/hello hello" "$TEST/part.img" >/dev/null 2>&1
debugfs -w -R "write $TEST/squash.img test.squashfs" "$TEST/part.img" >/dev/null 2>&1

truncate -s 64M "$TEST/disk.img"
parted -s "$TEST/disk.img" mklabel gpt mkpart primary ext4 1MiB 63MiB
dd if="$TEST/part.img" of="$TEST/disk.img" bs=1M seek=1 conv=notrunc status=none

accel=(-accel tcg)
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    accel=(-enable-kvm)
fi

set +e
timeout 180 qemu-system-x86_64 \
    "${accel[@]}" -m 512 -smp 1 \
    -kernel "$KERNEL" \
    -initrd "$TEST/initramfs.cpio.gz" \
    -append "console=ttyS0 panic=5" \
    -nographic -no-reboot \
    -drive file="$TEST/disk.img",if=virtio,format=raw,cache=unsafe \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    2>&1 | tee "$TEST/boot.log"
rc=${PIPESTATUS[0]}
set -e

if ! grep -q 'BOOT_OK' "$TEST/boot.log"; then
    die "boot did not reach BOOT_OK (qemu rc=$rc); see $TEST/boot.log"
fi

for marker in \
    "MODULES: 0" \
    "CONFIG_GZIP: yes" \
    "DISK_MOUNT: ok" \
    "SQUASHFS: ok" \
    "OVERLAY: ok" \
    "OVERLAY_WRITE: ok" \
    "NET: eth0" \
    "NFT: ok"
do
    grep -q "$marker" "$TEST/boot.log" || die "missing boot marker: $marker"
done

log "boot test passed: $TEST/boot.log"
