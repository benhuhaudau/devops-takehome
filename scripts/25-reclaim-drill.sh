#!/usr/bin/env bash
# scripts/25-reclaim-drill.sh: Part 2: prove the service survives a spot reclaim.
# 1. drain one spot node  2. curl loop while pods reschedule
# 3. verify placement recovered (>=1 on on-demand)  4. uncordon.
# Requires: kubectl. Idempotent: if the node is already cordoned it is un-cordoned at the end.
set -euo pipefail

SPOT_NAME=$(kubectl get nodes -l acme.io/capacity=spot -o jsonpath='{.items[0].metadata.name}')

echo "== Draining spot node: $SPOT_NAME =="
kubectl taint node "$SPOT_NAME" node.kubernetes.io/unschedulable:NoSchedule --overwrite >/dev/null || true
kubectl drain node "$SPOT_NAME" --ignore-daemonsets --delete-emptydir-data --force \
  --podgroups-request-limit=0 >/dev/null 2>&1 || true

echo "== Curl loop during rescheduling (15 tries, ~1s apart) =="
. "$(dirname "$0")/lib.sh" 2>/dev/null || true
FAIL=0
for i in $(seq 1 15); do
  if ! bash "$(dirname "$0")/smoke.sh" quote quote-api >/dev/null 2>&1; then
    FAIL=$((FAIL+1)); printf 'x'
  else
    printf '.'
  fi
  sleep 1
done
echo ""
echo "in-cluster checks failed during drill: $FAIL/15"

echo "== Waiting for placement recovery (>=1 replica on on-demand, >=2 ready) =="
ok=""
for _ in $(seq 1 60); do
  READY=$(kubectl -n quote get deployment/quote-api -o jsonpath='{.status.readyReplicas}')
  OD=$(kubectl -n quote get pods -l app.kubernetes.io/name=quote-api \
       -o jsonpath="{range .items[*]}{.spec.nodeName}{'\n'}{end}" 2>/dev/null \
       | while read n; do
           kubectl get node "$n" -o jsonpath='{.metadata.labels.acme\.io/capacity}' 2>/dev/null
         done | grep -c on-demand)
  if [ "${READY:-0}" -ge 2 ] && [ "$OD" -ge 1 ]; then ok=yes; break; fi
  sleep 3
done
[ "$ok" = yes ] || { echo "FAIL: placement did not recover"; kubectl get pods -n quote -o wide; exit 1; }
echo "Recovered: >=$READY ready, on-demand replicas=$OD"

echo "== Uncordon $SPOT_NAME =="
kubectl uncordon "$SPOT_NAME"
kubectl taint node "$SPOT_NAME" node.kubernetes.io/unschedulable- >/dev/null 2>&1 || true

echo "PASS: service survived spot reclaim"
