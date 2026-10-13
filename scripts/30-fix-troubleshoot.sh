#!/usr/bin/env bash
# scripts/30-fix-troubleshoot.sh: Part 3: apply fixed manifests and verify.
# Idempotent: applies troubleshoot/fixed-app.yaml then runs the PROVIDED
# verify.sh (network policy and node taints must survive untouched).
set -euo pipefail

kubectl apply -f /troubleshoot/fixed-app.yaml

echo "Waiting for troubleshoot workloads..."
kubectl -n troubleshoot rollout status deploy/web --timeout=180s
kubectl -n troubleshoot rollout status deploy/ai-inference --timeout=180s

echo "== Provided verifier =="
bash /troubleshoot/verify.sh
echo "PASS confirmed."
