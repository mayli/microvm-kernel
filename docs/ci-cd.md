# GitHub Actions → Release + Pages

One GitHub Actions run builds the kernel, boot-tests it, and publishes it to:

- a **GitHub Release** containing the `.deb` files, `vmlinuz`, config,
  `System.map` and checksums;
- a **GitHub Pages apt repository** for `apt install` / `apt upgrade`.

```text
daily schedule / manual
        │
        ▼
detect upstream stable linux in resolute
  - ignore Proposed/Backports
  - stop if a GitHub Release for this upstream already exists
        │
        ▼
build (Docker resolute builder)
  - make build
  - make boot-test (QEMU TCG)
        │
        ├── GitHub Release
        │     .deb + vmlinuz + config + System.map + SHA256SUMS
        │
        └── GitHub Pages
              signed apt repository (latest package set)
```

No Launchpad source upload or binary build is involved in the default
workflow.

## One-time setup

1. In the repository: **Settings → Pages → Build and deployment → Source:
   GitHub Actions**.
2. Add the apt-repository signing key as secrets:

   | Secret | Value |
   |---|---|
   | `GPG_PRIVATE_KEY` | base64 of the exported private key |
   | `GPG_KEY_ID` | key ID or full fingerprint |

   Use a dedicated signing key without an interactive passphrase in CI. The
   public key is published as `microvm-archive-keyring.asc` on Pages.

3. Ensure Actions are enabled and the repository has a `main` branch.

No PPA variables are needed unless you also use the manual Launchpad path.

## Schedule and triggers

`.github/workflows/release.yml`:

- **Daily at 04:17 UTC**: checks the newest stable `linux` source for
  `resolute` in Launchpad's Release, Updates and Security pockets.
- **Manual `workflow_dispatch`**: optional `force` input.

The detection script compares the upstream version with GitHub Releases whose
tags start with:

```text
kernel-<upstream>-
```

If a release exists, the workflow stops. `force` creates a new release with a
new run-based tag.

## Versions and assets

Example source/kernel version:

```text
7.0.0-43.43microvm42.1
```

Release tag:

```text
kernel-7.0.0-43.43-42.1
```

Release assets:

```text
linux-image-7.0.0-43-microvm_*.deb
linux-modules-7.0.0-43-microvm_*.deb
linux-headers-7.0.0-43-microvm_*.deb
linux-buildinfo-7.0.0-43-microvm_*.deb
vmlinuz-7.0.0-43-microvm
config-7.0.0-43-microvm
System.map-7.0.0-43-microvm
microvm.config
SHA256SUMS
```

## Pages apt repository

The Pages job creates:

```text
public/
├── dists/stable/InRelease
├── dists/stable/Release
├── dists/stable/Release.gpg
├── dists/stable/main/binary-amd64/Packages
├── dists/stable/main/binary-amd64/Packages.gz
├── pool/main/l/linux/*.deb
├── microvm-archive-keyring.asc
└── index.html
```

Users install with:

```sh
sudo install -m 0644 microvm-archive-keyring.asc \
  /usr/share/keyrings/microvm-archive-keyring.asc

echo "deb [signed-by=/usr/share/keyrings/microvm-archive-keyring.asc] \
https://OWNER.github.io/REPO stable main" \
  | sudo tee /etc/apt/sources.list.d/microvm.list

sudo apt update
sudo apt install linux-image-7.0.0-43-microvm
```

The apt metadata is generated with `apt-ftparchive` and signed with
`GPG_KEY_ID`; the kernel itself remains unsigned.

## Limits

- GitHub Pages published sites have a **1 GB** limit. The workflow publishes
  only the current build. Older versions stay in GitHub Releases for
  download/rollback.
- Release assets must be under **2 GiB** each; the kernel artifacts are tiny.
- Pages apt repository has no server-side redirects or dynamic metadata; all
  metadata is regenerated in CI.
- Upgrades across an ABI change (`7.0.0-43` → `7.0.0-44`) require installing
  the new package name, or adding a `linux-image-microvm` meta package.
- Kernel updates are not `apt`-installed if you use the base-swap/ubuntu-mini
  flow; the Release assets are the intended input.

## Manual local test

```sh
./scripts/in-container.sh make build
./scripts/boot-test.sh

# Inspect the Pages repository layout without signing:
ls out/debs
```

The manual Launchpad path remains available:

```sh
make source
debsign -kYOUR_GPG_KEY_ID work/linux_7.0.0-999.1_source.changes
make upload PPA=ppa:YOUR_USER/microvm
```

## Failure behavior

- If the scheduled detection says no new upstream release, no build runs.
- If the build or boot test fails, neither the Release nor the Pages deploy
  runs.
- If a Release was published but the Pages deploy failed, rerun the workflow
  with `force`; a new version/tag is created.
