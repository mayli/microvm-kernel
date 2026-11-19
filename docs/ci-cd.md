# GitHub Actions → Launchpad PPA

The kernel binary is **built and hosted by Launchpad**. GitHub Actions only
prepares and uploads the source package.

```text
schedule / tag / manual
          │
          ▼
GitHub Actions: make source
  - apt-get source linux=<latest stable resolute>
  - apply microvm config, annotations and packaging
  - dpkg-buildpackage -S
  - sign .changes with the Launchpad GPG key
          │
          ▼
dput ppa:OWNER/ARCHIVE
          │
          ▼
Launchpad: builds linux-image-*-microvm and publishes it in the PPA
```

## One-time setup

1. Create a PPA on Launchpad and enable **amd64 only**.
2. Import the GPG key you will use for uploads into Launchpad.
3. Create a dedicated signing key (preferably a signing-only subkey with no
   interactive passphrase in CI) and export it:

   ```sh
   gpg --armor --export-secret-keys YOUR_KEY_ID | base64 -w0
   ```

4. In the GitHub repository, set these **variables**:

   | Variable | Example |
   |---|---|
   | `PPA` | `ppa:YOUR_USER/microvm` |
   | `DEBFULLNAME` | `ubuntu-mini` |
   | `DEBEMAIL` | the email on the Launchpad signing key |

5. Set these **secrets**:

   | Secret | Value |
   |---|---|
   | `GPG_PRIVATE_KEY` | base64-encoded exported private key |
   | `GPG_KEY_ID` | the signing key ID/fingerprint |

6. Make sure the PPA exists before the first run. The workflow detects a
   missing PPA as “no previous source”, but `dput` still needs it.

## Schedule and triggers

`.github/workflows/ppa.yml` runs:

- **Daily at 04:17 UTC** — checks the newest stable `linux` source in
  `resolute` (Release, Updates and Security pockets; Proposed and Backports
  are ignored).
- **On a `kernel-*` tag** — forces a source build/upload with a unique version.
- **Manual `workflow_dispatch`** — optional `force` input.

The workflow uses the Launchpad API to compare the newest stable source
version with the source versions already published in the PPA. If the PPA
already has a source for that upstream version, the job stops before doing
any expensive work.

## Versions

The source version is:

```text
<upstream>microvm<run-number>.<run-attempt>
```

For example:

```text
7.0.0-43.43microvm42.1
```

The derived kernel packages are still:

```text
linux-image-7.0.0-43-microvm
linux-modules-7.0.0-43-microvm
```

The first upload uses `SOURCE_UPLOAD=sa` and includes the 244 MiB
`linux_7.0.0.orig.tar.gz`. Later uploads use `SOURCE_UPLOAD=sd` and omit the
orig tarball because the PPA already has it.

## Manual run

```sh
PPA=ppa:YOUR_USER/microvm \
GITHUB_RUN_NUMBER=1 \
GITHUB_RUN_ATTEMPT=1 \
python3 .github/scripts/check-upstream.py
```

To force a build locally:

```sh
SOURCE_UPLOAD=sa \
KERNEL_VERSION=7.0.0-43.43microvm1.1 \
UBUNTU_SOURCE_VERSION=7.0.0-43.43 \
make source
```

## Limitations

- If a source publication exists but the Launchpad binary build failed, the
  cron job treats that upstream version as already handled. Use a manual
  `force` run (new version) or delete the source publication in the PPA.
- The schedule follows Ubuntu's **stable** pockets. A version that is only in
  `-proposed` is intentionally ignored until it reaches updates/security.
- The signing key must be available to Launchpad and the same identity should
  be used for `DEBEMAIL`/`Changed-By`.
- The PPA build is unsigned for Secure Boot. This project does not use
  `linux-signed`.
- Public PPA means public source, config and build logs.
