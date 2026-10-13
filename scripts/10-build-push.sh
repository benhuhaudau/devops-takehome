#!/usr/bin/env bash
# scripts/10-build-push.sh: Part 1: build the quote-api image, load it into
# the cluster, and optionally push to GHCR.
# Idempotent. Safe to re-run.
#
# Reviewer mode (default): builds locally and imports into the k3d cluster,
# so no registry credentials are needed. The cluster falls back to the
# GHCR-pinned image if the local build step is skipped.
# CI/author mode: PUSH=1 additionally pushes ghcr.io/<repo>:<git-sha> + :latest
# (requires a prior docker login ghcr.io).
set -euo pipefail
export GIT_CONFIG_GLOBAL=/dev/null
git() { command git -c safe.directory='*' "$@"; }

ROOT=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || echo "")
[ -d "$ROOT/.git" ] || ROOT=/repo          # toolbox bind-mount layout
APP_DIR="${APP_DIR:-$ROOT/app/quote-api}"
[ -f "$APP_DIR/Dockerfile" ] || APP_DIR=/src/quote-api

IMAGE="${IMAGE:-ghcr.io/benhuhaudau/quote-api}"
TAG=$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo dev)

echo "== Building ${IMAGE}:${TAG} =="
docker build -t "${IMAGE}:${TAG}" -t "${IMAGE}:latest" "$APP_DIR"

echo "== Image info =="
docker image inspect "${IMAGE}:${TAG}" --format '{{.Size}} bytes  {{.Os}}/{{.Architecture}}'

echo "== Loading image into the k3d cluster =="
k3d image import "${IMAGE}:${TAG}" "${IMAGE}:latest" -c takehome

if [ "${PUSH:-0}" = "1" ]; then
  echo "== Pushing =="
  docker push "${IMAGE}:${TAG}"
  docker push "${IMAGE}:latest"
  echo "Pushed ${IMAGE}:${TAG} (+latest)"
else
  echo "PUSH=0 (default): image stays local. Set PUSH=1 to publish to GHCR."
fi
