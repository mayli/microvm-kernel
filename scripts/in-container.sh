#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_cmd docker

image="${BUILDER_IMAGE:-microvm-kernel-builder}"

if ! docker image inspect "$image" >/dev/null 2>&1; then
    log "building container image $image"
    docker build -t "$image" -f "$ROOT/docker/Dockerfile" "$ROOT"
fi

exec docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -v "$ROOT:$ROOT" \
    -w "$ROOT" \
    "$image" "$@"
