#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-$ROOT/work}"
SRC="${SRC:-$WORK/linux}"
OUT="${OUT:-$ROOT/out}"

CONFIG_UPSTREAM="$ROOT/config/upstream"
CONFIG_FRAGMENTS="$ROOT/config/fragments"

UBUNTU_REPO="${UBUNTU_REPO:-https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/resolute}"
UBUNTU_TAG="${UBUNTU_TAG:-Ubuntu-7.0.0-43.43}"
UBUNTU_SOURCE_VERSION="${UBUNTU_SOURCE_VERSION:-7.0.0-43.43}"
USE_APT_SOURCE="${USE_APT_SOURCE:-1}"
KERNEL_VERSION="${KERNEL_VERSION:-7.0.0-999.1}"
PPA="${PPA:-ppa:CHANGE_ME/microvm}"

log() {
    printf '==> %s\n' "$*"
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

require_file() {
    [[ -f "$1" ]] || die "missing file: $1"
}

require_src() {
    [[ -f "$SRC/debian/rules" ]] || die "kernel source missing at $SRC; run 'make prepare'"
}
