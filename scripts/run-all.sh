#!/usr/bin/env bash
# scripts/run-all.sh: the ONLY entry point the reviewer needs.
# Requires nothing but docker (+ docker compose) on the host.
#   git clone <repo> && cd <repo>
#   docker compose up -d        # starts cluster + toolbox (bootstrap included)
#   ./scripts/run-all.sh        # (or per-script, see below)
# If the harness toolbox is running, ALL task execution happens inside it
# (its kubeconfig always points at the takehome cluster: the host's own
# kubeconfig, if any, is never trusted).
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)

route_into_toolbox() {
  echo "Routing task execution into the toolbox container..."
  echo "Waiting for cluster bootstrap to complete (first run can take a few minutes)..."
  deadline=$(( $(date +%s) + 900 ))
  until docker compose ps --status running 2>/dev/null | grep -q toolbox; do
    docker compose up -d >/dev/null 2>&1 || true
    [ "$(date +%s)" -lt "$deadline" ] || { echo "Timed out waiting for toolbox"; exit 1; }
    sleep 5
  done
  exec docker compose exec -T toolbox /scripts/run-all.sh "$@"
}

if command -v docker >/dev/null 2>&1 && docker compose ps toolbox 2>/dev/null | grep -q tool; then
  # Prefer the toolbox even if the host has its own kubectl: its kubeconfig
  # always targets this repo's cluster; the host's may point elsewhere.
  route_into_toolbox "$@"
elif ! command -v kubectl >/dev/null 2>&1 && command -v docker >/dev/null 2>&1; then
  route_into_toolbox "$@"
fi

# Fallback: local execution (only if a kubectl pointed at the takehome cluster exists)
TARGET="${1:-all}"
run() { echo ""; echo "== [$(basename "$1")]"; bash "$1"; }
OK=0; FAILED=""
if [ "$TARGET" = "all" ]; then
  for s in "$HERE"/[0-9]*-*.sh; do
    case "$(basename "$s")" in run-all.sh) continue ;; esac
    if run "$s"; then OK=$((OK+1)); else FAILED="$FAILED $(basename "$s")"; fi
  done
else
  # NOTE: globs do not expand in assignments, so use compgen to test/select
  s=$(compgen -G "$HERE/${TARGET}-*.sh" | head -n1)
  if [ -z "${s:-}" ]; then echo "unknown task: $TARGET"; exit 1; fi
  if run "$s"; then OK=$((OK+1)); else FAILED="$(basename "$s")"; fi
fi

echo ""
if [ -n "$FAILED" ]; then
  echo "Done. OK=$OK  FAILED:$FAILED"
  exit 1
fi
echo "Done. $OK task(s) OK."
