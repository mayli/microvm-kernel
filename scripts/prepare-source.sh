#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_cmd git
require_cmd python3

log "Ubuntu source: $UBUNTU_REPO"
log "Ubuntu tag:    $UBUNTU_TAG"
log "Version:       $KERNEL_VERSION"

if [[ ! -d "$SRC/.git" ]]; then
    mkdir -p "$WORK"
    log "cloning kernel source (shallow)"
    git clone --depth 1 --branch "$UBUNTU_TAG" "$UBUNTU_REPO" "$SRC"
else
    log "reusing existing source tree: $SRC"
fi

cd "$SRC"

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

text = re.sub(r"(?m)^flavours\s*=.*$", "flavours\t= generic microvm", text)

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
