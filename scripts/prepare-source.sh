#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_cmd python3

prepare_with_apt() {
    require_cmd apt-get
    require_cmd dpkg-source

    local dir="$WORK/apt-source"
    mkdir -p "$dir/etc" "$dir/lists/partial" \
             "$dir/cache/archives/partial" "$dir/src"

    cat > "$dir/etc/sources.list" <<'EOF'
deb-src http://archive.ubuntu.com/ubuntu/ resolute main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ resolute-updates main restricted universe multiverse
deb-src http://security.ubuntu.com/ubuntu/ resolute-security main restricted universe multiverse
EOF

    local -a apt_opts=(
        -o "Dir::Etc::sourcelist=$dir/etc/sources.list"
        -o "Dir::Etc::sourceparts=-"
        -o "Dir::State::lists=$dir/lists"
        -o "Dir::Cache=$dir/cache"
        -o "APT::Sandbox::User="
        -o "APT::Get::List-Cleanup=0"
    )

    log "apt-get update (source indexes)"
    if ! apt-get "${apt_opts[@]}" update >"$dir/apt-update.log" 2>&1; then
        tail -n 60 "$dir/apt-update.log" >&2 || true
        die "apt-get update failed"
    fi

    log "apt-get source linux=$UBUNTU_SOURCE_VERSION"
    if ! ( cd "$dir/src" && apt-get "${apt_opts[@]}" source "linux=$UBUNTU_SOURCE_VERSION" ) \
            >"$dir/apt-source.log" 2>&1; then
        tail -n 80 "$dir/apt-source.log" >&2 || true
        die "apt-get source failed"
    fi

    local unpacked
    unpacked="$(find "$dir/src" -maxdepth 1 -mindepth 1 -type d -name 'linux-*' \
        -print -quit)"
    [[ -n "$unpacked" ]] || die "apt-get source did not unpack a linux-* tree"

    mv "$unpacked" "$SRC"

    # Keep the source-package files next to the tree for 'make source'.
    find "$dir/src" -maxdepth 1 -type f \
        \( -name 'linux_*.orig.tar.*' -o -name 'linux_*.dsc' -o -name 'linux_*.diff.*' \) \
        -exec cp -v {} "$WORK/" \;
}

log "Ubuntu source version: $UBUNTU_SOURCE_VERSION"
log "Version:               $KERNEL_VERSION"

if [[ -f "$SRC/debian/rules" ]]; then
    log "reusing existing source tree: $SRC"
else
    [[ ! -e "$SRC" ]] || die "$SRC exists but is not a kernel source tree"
    mkdir -p "$WORK"

    if [[ "$USE_APT_SOURCE" == "1" ]]; then
        prepare_with_apt
    else
        require_cmd git
        log "cloning kernel source (shallow)"
        git clone --depth 1 --branch "$UBUNTU_TAG" "$UBUNTU_REPO" "$SRC"
    fi
fi

cd "$SRC"

# Packaging overlays maintained in this repository.
if [[ -d "$ROOT/packaging" ]]; then
    log "installing packaging overlays"
    cp -a "$ROOT/packaging/." "$SRC/"
fi

# Ubuntu's packaging assumes at least one loadable module.  This kernel has
# none, so guard the module.lds copy, the watchdog blacklist and the ABI
# compiler-info extraction.
if ! grep -q "Copy over scripts/module.lds for building external modules, when present" \
        "$SRC/debian/rules.d/2-binary-arch.mk"; then
    log "applying no-modules packaging patch"
    ( cd "$SRC" && patch -p1 --forward < "$ROOT/patches/2-binary-arch-no-modules.patch" )
fi

python3 - "$KERNEL_VERSION" <<'PY'
import email.utils
import os
import re
import sys
from pathlib import Path

version = sys.argv[1]
root = Path.cwd()

# ---------------------------------------------------------------------------
# amd64 flavour list and build switches
# ---------------------------------------------------------------------------
rules = root / "debian.master/rules.d/amd64.mk"
text = rules.read_text()

text = re.sub(r"(?m)^flavours\s*=.*$", "flavours\t= microvm", text)

if re.search(r"(?m)^uefi_signed\s*=", text):
    text = re.sub(r"(?m)^uefi_signed\s*=.*$", "uefi_signed = false", text)
else:
    text += "\nuefi_signed = false\n"

for key, value in (
    ("do_skip_checks", "true"),
    ("do_tools", "false"),
    ("do_dbgsym_package", "false"),
):
    if re.search(rf"(?m)^{key}\s*=", text):
        text = re.sub(rf"(?m)^{key}\s*=.*$", f"{key} = {value}", text)
    else:
        text += f"{key} = {value}\n"

rules.write_text(text)

# ---------------------------------------------------------------------------
# annotations header
# ---------------------------------------------------------------------------
annotations = root / "debian.master/config/annotations"
text = annotations.read_text()
match = re.search(r"(?m)^# FLAVOUR: (.*)$", text)
if not match:
    raise SystemExit("annotations header has no '# FLAVOUR:' line")

flavours = match.group(1).split()
if "amd64-microvm" not in flavours:
    flavours.append("amd64-microvm")
    text = text[:match.start()] + "# FLAVOUR: " + " ".join(flavours) + text[match.end():]
    annotations.write_text(text)

# ---------------------------------------------------------------------------
# changelog: prepend a custom entry once
# ---------------------------------------------------------------------------
changelog = root / "debian.master/changelog"
text = changelog.read_text()
first_line = text.splitlines()[0] if text else ""

if f"({version})" not in first_line:
    name = os.environ.get("DEBFULLNAME", "ubuntu-mini")
    email_addr = os.environ.get("DEBEMAIL", "ubuntu-mini@localhost")
    date = email.utils.formatdate(localtime=True)
    entry = (
        f"linux ({version}) resolute; urgency=medium\n\n"
        "  * Custom microvm flavour for ubuntu-mini: monolithic guest kernel,\n"
        "    no loadable modules, virtio/squashfs/overlayfs built in.\n\n"
        f" -- {name} <{email_addr}>  {date}\n\n"
    )
    changelog.write_text(entry + text)
PY

# dpkg wants debian/changelog before debian/rules clean has a chance to run.
cp -f debian.master/changelog debian/changelog

chmod +x debian/rules
find debian/scripts -type f -exec chmod +x {} +

abi="${KERNEL_VERSION#*-}"
abi="${abi%%.*}"
package_version="${KERNEL_VERSION%%-*}-${abi}"

log "prepared $SRC"
log "flavour microvm added; package will be linux-image-${package_version}-microvm"
