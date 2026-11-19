# Ubuntu microvm kernel builds

Build and publish a minimal, monolithic Ubuntu kernel for the `ubuntu-mini`
guest VMs.

- **Ubuntu source:** `linux` `7.0.0-43.43`, `resolute` (26.04), tag
  `Ubuntu-7.0.0-43.43`
- **Flavour:** `microvm`
- **Config seed:** Firecracker's
  `microvm-kernel-ci-x86_64-6.18.config`, plus its `ci.config` and
  `efi.config` fragments
- **Output:** `linux-image-<upstream>-microvm` — unsigned, no loadable modules
- **Target:** QEMU/KVM guest with virtio-blk/net/console, GPT + ext4,
  squashfs + overlayfs
- **Signing:** kernel unsigned; the GitHub Pages apt repo is signed.
  Secure Boot is out of scope.
- **Distribution:** GitHub Releases for archives plus a GitHub Pages apt
  repository for `apt install` / `apt upgrade`

The optional meta package `linux-image-microvm` is not required for
ubuntu-mini's base-swap tooling. Use the versioned package or extract its
`vmlinuz`.

## Quick start

`make prepare` uses `apt-get source linux=7.0.0-43.43` by default. That gives
the exact archive source tree. Set `USE_APT_SOURCE=0` to clone the Launchpad
git tag instead.

The build host needs a resolute/26.04 build environment. If the host is
missing kernel build dependencies, build inside the provided container:

```sh
./scripts/in-container.sh make config
./scripts/in-container.sh make build
```

On a host with `deb-src` and the kernel build dependencies installed:

```sh
sudo apt update
sudo apt build-dep -y linux
sudo apt install -y fakeroot dpkg-dev devscripts dput

make prepare
make config
make verify
make build
```

The build writes `.deb` files and the extracted `vmlinuz` under `out/`.

After a build, run the QEMU boot test:

```sh
make boot-test
```

The GitHub Actions workflow builds, boot-tests and publishes the kernel to a
GitHub Release and a GitHub Pages apt repository. See
[`docs/ci-cd.md`](docs/ci-cd.md).

The older Launchpad source-upload path is still available manually:

```sh
make source
debsign -kYOUR_GPG_KEY_ID work/linux_7.0.0-999.1_source.changes
make upload PPA=ppa:YOUR_USER/microvm
```

The first source upload includes the ~255 MiB `linux_7.0.0.orig.tar.gz`.
Later uploads can reuse it with `SOURCE_UPLOAD=sd`. `make source`
deliberately builds an unsigned source package.

## Why this exists

The stock Ubuntu generic kernel has `overlayfs`, many netfilter pieces, and
other drivers as modules. ubuntu-mini wants a kernel that can boot a
virtio-backed guest, mount a squashfs file over a writable overlay, and run
UFW without carrying a module tree or matching `overlay.ko`.

Firecracker's microVM config is already a monolithic guest config with no
`=m` entries. This project reuses that config, adapts it to Ubuntu 26.04 and
adds the missing pieces for GPT partitions, UFW/nftables, and optionally
AppArmor.

## Layout

```text
config/upstream/     Vendored Firecracker configs (pinned commit)
config/fragments/    Our overrides, applied after the upstream fragments
patches/             Ubuntu packaging guards for a kernel with no modules
packaging/           Extra control.d flavour metadata
docker/              Reproducible resolute build container
.github/             GitHub Actions build/release workflow and upstream check
scripts/             prepare, render, verify, build, boot test, source, upload
docs/decisions.md    What we chose and why
docs/ci-cd.md        GitHub Actions → Release + Pages setup and schedule
docs/plan.md         Phases, tests, acceptance criteria, risks
work/                Ubuntu kernel source clone and build output (ignored)
out/                 Collected .debs, vmlinuz, rendered config (ignored)
```

## Requirements and limitations

- The local build needs a resolute build environment; GitHub Actions uses the
  provided container.
- Expect a kernel build of roughly 10–20 minutes in CI on a 4-core runner,
  because debug info, modules, tools and DKMS are disabled.
- The result is **unsigned**. Do not use it with Secure Boot unless you sign
  it yourself.
- `CONFIG_MODULES=n` means no loadable modules, no `/lib/modules` tree, and no
  `overlay.ko`. Any feature needed at boot or runtime must be built in.
- Adding the flavour to `debian.master/config/annotations` produces a large
  annotations diff. That is expected.
