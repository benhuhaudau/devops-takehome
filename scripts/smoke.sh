#!/usr/bin/env bash
# scripts/smoke.sh: in-cluster smoke test of the quote-api via its ClusterIP Service
# Usage: ./scripts/smoke.sh [namespace] [service]
set -eu
NS="${1:-quote}"
SVC="${2:-quote-api}"
NAME="smoke-check-${RANDOM}"

cleanup() { kubectl delete pod "$NAME" -n "$NS" --force --grace-period=0 >/dev/null 2>&1 || true; }
trap cleanup EXIT

kubectl delete pod "$NAME" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
kubectl -n "$NS" run "$NAME" \
  --image=curlimages/curl:8.7.1 \
  --restart=Never \
  --command -- sh -c "curl -fsS --max-time 5 --retry 3 --retry-delay 1 http://${SVC}.${NS}.svc.cluster.local:80/api/quote" >/dev/null

for _ in $(seq 1 20); do
  S=$(kubectl -n "$NS" get pod "$NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo Pending)
  [ "$S" = "Succeeded" ] && break
  [ "$S" = "Failed" ] && break
  sleep 2
done

echo "pod phase: $S"
kubectl -n "$NS" logs "$NAME" 2>/dev/null || true
[ "$S" = "Succeeded" ] || exit 1
