# Plan

Status: repository scaffolded. Nothing has been built or boot-tested yet.

## Phase 0 — scaffold

- [x] Initialise this git repository
- [x] Vendor the pinned Firecracker config and fragments
- [x] Add config overrides, scripts and Makefile
- [ ] Review and adjust the UFW/AppArmor fragments on a real target

## Phase 1 — local config and build

Commands:

```sh
make prepare
make config
make verify
make build
```

Acceptance:

- [ ] `make config` completes and writes `out/microvm.config`
- [ ] `grep '=m' .config` is empty
- [ ] `CONFIG_MODULES` is not set
- [ ] `CONFIG_EFI_PARTITION=y`
- [ ] `CONFIG_VIRTIO_BLK/NET/PCI/CONSOLE=y`
- [ ] `CONFIG_SQUASHFS`, `CONFIG_BLK_DEV_LOOP`, `CONFIG_OVERLAY_FS` are `=y`
- [ ] `CONFIG_NF_TABLES_INET=y`
- [ ] `make build` produces `linux-image-7.0.0-999-microvm`
- [ ] `out/vmlinuz-7.0.0-999-microvm` exists

## Phase 2 — boot tests

Use QEMU/KVM with virtio-blk and a GPT disk. Test in this order:

1. Direct `-kernel` boot of the new `vmlinuz`, root on the existing ext4
   partition, `root=PARTUUID=...`, no initrd.
2. Same kernel with the squashfs base + overlay setup (custom initramfs and
   ext4 bootstrap).
3. UFW and nftables on the booted guest.

Acceptance:

- [ ] `uname -r` is `7.0.0-999-microvm`
- [ ] `/proc/config.gz` exists and matches `out/microvm.config`
- [ ] `lsmod` is empty; `modprobe overlay` fails (no module support)
- [ ] GPT partition and `PARTUUID=` root work
- [ ] virtio-blk, virtio-net and virtio-console work
- [ ] squashfs file mounts, overlayfs works, persistence works
- [ ] `ufw enable`, `ufw status`, and a simple allow/deny rule work
- [ ] `nft list ruleset` works
- [ ] no `/lib/modules` directory is needed to boot
- [ ] no `overlay.ko` is needed by the initramfs/bootstrap
- [ ] a reboot with the previous squashfs/base still works

## Phase 3 — public PPA

Prerequisites:

- Launchpad account and a PPA named `microvm` (or another name)
- GPG key registered with Launchpad
- `dput` configured

Commands:

```sh
make source
make upload PPA=ppa:YOUR_USER/microvm
```

Acceptance:

- [ ] Launchpad builds `amd64` successfully
- [ ] `.changes` includes the orig tarball on the first upload
- [ ] the PPA contains `linux-image-7.0.0-999-microvm`
- [ ] the PPA contains `linux-modules-7.0.0-999-microvm` with config/System.map
      but no `.ko` files
- [ ] build log is public and has no signing step
- [ ] the built package boots on the target

## Phase 4 — ubuntu-mini integration

- [ ] Replace the generic `vmlinuz`/`initrd` inputs with the microvm kernel
- [ ] Remove the 221-module trim and `/lib/modules` from the target-ready base
- [ ] Remove `overlay.ko` from the initramfs/bootstrap
- [ ] Update the base-swap tooling to record the new kernel version and ABI
- [ ] Keep the old generic kernel entry for rollback until the new one is
      validated
- [ ] Measure the new base size and boot time

## Risks / open questions

- **Annotations import size:** adding a full new flavour to
  `debian.master/config/annotations` creates a large diff. Acceptable for a
  custom PPA; inspect it before uploading.
- **UFW coverage:** the Firecracker config was not built for UFW. The fragment
  is a best-effort list; verify with the actual `ufw`/`nft` userspace. Add
  missing matches/targets if a rule fails.
- **6.18 → 7.0 drift:** `olddefconfig` may change defaults or drop symbols.
  Always inspect `out/microvm.config` and the annotations diff.
- **GPT vs EFI:** `EFI_PARTITION` is required even on BIOS. Do not remove it
  just because `EFI`/`EFI_STUB` are unused.
- **No modules:** any feature not built in is unavailable. Confirm the exact
  virtio transport (PCI vs MMIO), disk type (blk vs scsi), and network setup
  before building.
- **Source package format:** the Ubuntu kernel source is Debian format `1.0`
  and needs `linux_7.0.0.orig.tar.gz`. The first PPA upload is large.
- **Public PPA:** everything is public. Do not include secrets in configs,
  changelog entries or scripts.
- **Unsigned kernel:** do not enable Secure Boot on the target; it will not
  boot this kernel.
