# Ubuntu microvm kernel

Minimal, monolithic Ubuntu kernel for `ubuntu-mini` QEMU/KVM guests.

- Ubuntu `linux` `7.0.0-43.43` (`resolute`, 26.04)
- Flavour: `microvm`
- Config seed: Firecracker `microvm-kernel-ci-x86_64-6.18.config`
  plus `ci.config` and `efi.config`
- Unsigned, **no loadable modules**
- virtio-blk/net/console, GPT, ext4, squashfs, overlayfs, UFW/netfilter,
  AppArmor

GitHub Actions builds and boot-tests the kernel, publishes a GitHub Release,
and deploys a signed apt repository to GitHub Pages.

## Local build

```sh
./scripts/in-container.sh make build
make boot-test
```

Outputs:

```text
out/vmlinuz-7.0.0-43-microvm
out/debs/linux-image-7.0.0-43-microvm_*.deb
out/debs/linux-modules-7.0.0-43-microvm_*.deb
out/microvm.config
```

Local `make prepare/config/verify/build` also works on a resolute host with
the kernel build dependencies installed. `make prepare` uses
`apt-get source linux=7.0.0-43.43`; set `USE_APT_SOURCE=0` to use the
Launchpad git tag instead.

## CI/CD

`.github/workflows/release.yml` runs daily at 04:17 UTC and on manual
dispatch. It:

1. Finds the newest stable `linux` source for `resolute` in Launchpad's
   Release/Updates/Security pockets.
2. Stops if a `kernel-<upstream>-*` GitHub Release already exists.
3. Builds and boot-tests the kernel.
4. Publishes `.deb`, `vmlinuz`, config, `System.map` and `SHA256SUMS` to a
   GitHub Release.
5. Deploys a signed apt repository to GitHub Pages.

Manual rebuild:

```sh
gh workflow run microvm-kernel-release \
  -R mayli/microvm-kernel \
  -f force=true
```

### Required setup

- **Settings → Pages → Source: GitHub Actions**
- Repository secrets:
  - `GPG_PRIVATE_KEY`: base64 of the apt-repo signing key
  - `GPG_KEY_ID`: key ID/fingerprint

The GitHub Pages apt repository contains only the current build. Older
versions remain in GitHub Releases. The kernel is unsigned; the apt metadata
is signed.

## Install from Pages

Download `microvm-archive-keyring.asc` and use the URL shown on the Pages
index page:

```sh
sudo install -m 0644 microvm-archive-keyring.asc \
  /usr/share/keyrings/microvm-archive-keyring.asc

echo "deb [signed-by=/usr/share/keyrings/microvm-archive-keyring.asc] \
https://OWNER.github.io/REPO stable main" \
  | sudo tee /etc/apt/sources.list.d/microvm.list

sudo apt update
sudo apt install linux-image-7.0.0-43-microvm
```

## Layout

```text
config/upstream/     Pinned Firecracker configs
config/fragments/    Project overrides
patches/             No-modules packaging guards
packaging/           microvm flavour control metadata
docker/              Resolute build container
.github/             Release workflow and upstream check
scripts/             prepare, config, build, boot-test
work/                Source and build output (ignored)
out/                 Release artifacts (ignored)
```

## Limits

- The kernel has no module support. Anything not built in is unavailable.
- The Pages site has a 1 GB limit; only the current package set is published.
- The kernel is unsigned; Secure Boot is out of scope.
- ABI changes (`7.0.0-43` → `7.0.0-44`) require installing the new package
  name unless a meta package is added.
