#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_cmd dput

if [[ "$PPA" == *CHANGE_ME* ]]; then
    die "set PPA=ppa:YOUR_USER/microvm"
fi

changes="$(find "$WORK" -maxdepth 1 -type f -name 'linux_*_source.changes' \
    -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2- || true)"

[[ -n "$changes" ]] || die "no source .changes file; run 'make source' first"

log "uploading to $PPA"
dput "$PPA" "$changes"

user_and_ppa="${PPA#ppa:}"
user="${user_and_ppa%%/*}"
ppa="${user_and_ppa##*/}"

log "upload submitted; watch the PPA build page"
log "https://launchpad.net/~${user}/+archive/ubuntu/${ppa}"
