#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_cmd docker

image="${BUILDER_IMAGE:-microvm-kernel-builder}"

if ! docker image inspect "$image" >/dev/null 2>&1; then
    log "building container image $image"
    docker build -t "$image" -f "$ROOT/docker/Dockerfile" "$ROOT"
fi

env_args=()
for var in KERNEL_VERSION UBUNTU_SOURCE_VERSION SOURCE_UPLOAD USE_APT_SOURCE \
           UBUNTU_TAG UBUNTU_REPO DEBFULLNAME DEBEMAIL; do
    if [[ -n "${!var:-}" ]]; then
        env_args+=(--env "$var=${!var}")
    fi
done

exec docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    "${env_args[@]}" \
    -v "$ROOT:$ROOT" \
    -w "$ROOT" \
    "$image" "$@"
