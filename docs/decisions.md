# Decisions

Status: agreed direction, not yet built or boot-tested.

## Goal

Provide a small Ubuntu 26.04 `resolute` kernel for the `ubuntu-mini` guest VPS
that has the boot and runtime pieces it needs built in, instead of depending on
the stock generic module tree.

The target is a QEMU/KVM guest with:

- virtio-blk root on a GPT disk, ext4
- virtio-net and virtio-console
- read-only squashfs base + writable overlayfs
- UFW/nftables
- BIOS/GRUB, no Secure Boot

## Source input

Use `apt-get source linux=7.0.0-43.43` as the default source input. It:

- gives the exact source tree that the archive/Launchpad uses
- provides `linux_7.0.0.orig.tar.gz`, which Debian source format `1.0`
  needs for a PPA upload
- avoids carrying a 2 GiB git clone and its `.git` directory

`USE_APT_SOURCE=0` switches to the Launchpad git tag for comparison or
bisecting. The two inputs should describe the same source version.

## Flavour and package names

- Flavour: `microvm`
- Real kernel package: `linux-image-7.0.0-999-microvm`
- Optional meta package: `linux-image-microvm`
- `uname -r`: `7.0.0-999-microvm`

The custom ABI `999` keeps the package clearly separate from the archive's
`7.0.0-43-generic`. The source package remains the Ubuntu `linux` source; only
a new flavour is added.

`uefi_signed = false` is set so the `linux` source produces
`linux-image-<abi>-microvm` rather than `linux-image-unsigned-<abi>-microvm`.
The kernel is still unsigned; this switch only selects the packaging name.

## Why `microvm` and why no modules

Firecracker's guest config is already a monolithic microVM kernel with zero
`=m` entries. It has the important pieces `=y`:

- `VIRTIO_PCI`, `VIRTIO_BLK`, `VIRTIO_NET`, `VIRTIO_CONSOLE`,
  `VIRTIO_BALLOON`, `VIRTIO_VSOCKETS`
- `SQUASHFS`, `BLK_DEV_LOOP`, `OVERLAY_FS`, `EXT4_FS`
- `DEVTMPFS`, `DEVTMPFS_MOUNT`, `TMPFS`
- `CGROUPS`, `NAMESPACES`, `SECCOMP`, `NETFILTER`,
  `NF_CONNTRACK`, `NF_NAT`, `BRIDGE`, `VETH`

`CONFIG_MODULES=n` is a deliberate extra step:

- no `/lib/modules` tree is required
- no `overlay.ko` is needed by the initramfs or ext4 bootstrap
- no module signing/tooling
- the base can drop the 221-module UFW/overlay trim

The cost is that any missing driver must be built in or the feature is simply
unavailable. That is acceptable for this fixed guest profile.

## Firecracker config provenance

Pinned to Firecracker commit `4e65d4309c355925872b9d3006f18eef96653645`:

```text
config/upstream/microvm-kernel-ci-x86_64-6.18.config  # full base
config/upstream/ci.config                             # fragment
config/upstream/efi.config                            # fragment
```

The base is for 6.18; Ubuntu's source is 7.0.0. `make olddefconfig` adapts
renamed/new symbols. Review the result; do not assume the 6.18 symbols map
one-to-one.

## Fragment choices

### `10-microvm.config`

- `CONFIG_MODULES=n`
- `CONFIG_EFI_PARTITION=y`
  - Needed for GPT partition parsing. This is **not** UEFI firmware; the VPS
    boots BIOS but its disk is GPT. The `efi.config` fragment also sets it.
- Disable `DEVMEM` (public kernel, no need for `/dev/mem`)
- Disable `SERIO` / keyboard input (headless guest)
- Disable `DAMON`
  - Firecracker's CI config enables it, but the guest does not need it.
  - Ubuntu 7.0.0-43.43 has a latent DAMON build error
    (`mm/damon/core.c` uses `min_sz_region` instead of the function parameter
    `min_region_sz`); generic builds hide it with `CONFIG_DAMON=n`.
- Keep `IKCONFIG`/`IKCONFIG_PROC` for `/proc/config.gz`
- Keep `MSDOS_PARTITION` for MBR images

### `20-ufw-netfilter.config`

The Firecracker base has legacy IPv4/IPv6 tables and several nftables pieces,
but not all of them. UFW on Ubuntu may use the nftables backend, so enable the
missing nftables families/targets and xtables matches:

- `NF_TABLES_INET`, `NF_TABLES_IPV6`, `NFT_COMPAT`
- `NFT_MASQ`, `NFT_REJECT`, `NFT_LOG`, `NFT_LIMIT`
- `NETFILTER_XT_MATCH_STATE`, `_COMMENT`, `_MULTIPORT`, `_LIMIT`
- logging and CT targets

This must be verified on the target with `ufw status` and `nft list ruleset`.

### `30-apparmor.config`

Ubuntu userspace expects AppArmor. The Firecracker config defaults to SELinux
and has AppArmor disabled. The fragment enables AppArmor and sets Ubuntu's LSM
order. Remove the fragment if the guest image does not ship `apparmor`.

## No-modules packaging patch

Ubuntu's `debian/rules.d/2-binary-arch.mk` assumes that a kernel has at least
one loadable module. With `CONFIG_MODULES=n`, the build has no
`scripts/module.lds`, `Module.symvers`, `modules.order`, watchdog module
directory, or `.ko` from which to read compiler info. The patch in
`patches/2-binary-arch-no-modules.patch` guards those steps. It does not
change the kernel image or config; it only makes the package assembly work
for a monolithic kernel.

`packaging/debian.master/control.d/vars.microvm` adds the flavour metadata
needed to generate `linux-image-7.0.0-999-microvm` in `debian/control`.

## CI/CD boundary

GitHub Actions prepares and uploads the source package. It never builds or
uploads kernel binaries. Launchpad remains the only binary builder and the
PPA remains the distribution point.

A daily workflow checks the stable `linux` source version in the `resolute`
archive and compares it with published sources in the PPA. If upstream
changed, CI builds a source package and `dput`s it; Launchpad builds the
kernel. See `docs/ci-cd.md`.

A Launchpad-native recipe was considered but rejected for this tree: the
Ubuntu source is Debian format `1.0` and needs the 244 MiB orig tarball,
which a recipe cannot obtain with `apt-get source`, and maintaining a 1.8 GiB
source branch on Launchpad is unnecessary.

## Signing, PPA and distribution

- Kernel image signing: **not required**. Secure Boot is out of scope.
- `linux-signed`, Canonical signing keys, and `sbsign` are not used.
- PPA: **public**. Build logs, source and config are public.
- Launchpad builds only `amd64`.
- The source is Ubuntu's `linux` source with a custom changelog version; the
  PPA is separate from the archive, so there is no package-name collision.

## Non-goals

- Secure Boot
- DKMS, ZFS, v4l2loopback, tools, perf, debug packages
- general-purpose hardware support
- replacing the archive's `linux-image-generic`
- automatic apt upgrades of the kernel inside the overlay
