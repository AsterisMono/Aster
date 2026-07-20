#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-localhost/aster-builder}"
JOBS="${JOBS:-$(nproc)}"
ENGINE="${ENGINE:-}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "JOBS must be a positive integer (got '$JOBS')"

if [ -z "$ENGINE" ]; then
  if command -v podman >/dev/null 2>&1; then
    ENGINE=podman
  elif command -v docker >/dev/null 2>&1; then
    ENGINE=docker
  else
    die "Docker or Podman is required"
  fi
fi
command -v "$ENGINE" >/dev/null 2>&1 || die "Container engine '$ENGINE' was not found"

VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/chromium_version.txt")"
OUTPUT="$REPO_ROOT/aster-$VERSION.rpm"

printf '==> Container engine: %s\n' "$ENGINE"
printf '==> Building amd64 builder image: %s\n' "$IMAGE"
"$ENGINE" build \
  --platform linux/amd64 \
  --tag "$IMAGE" \
  --file "$REPO_ROOT/scripts/build.Dockerfile" \
  "$REPO_ROOT"

run_args=(
  --rm
  --interactive
  --platform linux/amd64
  --volume "$REPO_ROOT:/uc:Z"
  --workdir /uc
  --env HOME=/tmp
  --env "JOBS=$JOBS"
)

# Docker does not remap container root in the way rootless Podman does. Run as
# the caller so the persistent build tree and RPM are not owned by root.
if [ "$ENGINE" = docker ]; then
  run_args+=(--user "$(id -u):$(id -g)")
fi
[ -t 0 ] && run_args+=(--tty)

printf '==> Building Aster %s (JOBS=%s)\n' "$VERSION" "$JOBS"
"$ENGINE" run "${run_args[@]}" "$IMAGE"

[ -f "$OUTPUT" ] || die "container completed without producing $OUTPUT"
printf '==> RPM ready: %s\n' "$OUTPUT"
