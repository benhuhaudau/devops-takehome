#!/usr/bin/env bash
# scripts/20-deploy.sh: Part 2: ArgoCD + GitOps deploy of quote-api
# Idempotent: helm upgrade --install ArgoCD, then apply a self-syncing
# ArgoCD Application whose source is THIS git repo (chart path config/charts/quote-api).
# Requires: kubectl, helm, git.
# Env:
#   IMAGE_REPO (default ghcr.io/acme-takehome/quote-api)
#   IMAGE_TAG  (default: git short SHA; falls back to latest if not measurable)
set -euo pipefail
export GIT_CONFIG_GLOBAL=/dev/null
git() { command git -c safe.directory='*' "$@"; }

ROOT=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || echo "")
[ -d "$ROOT/.git" ] || ROOT=/repo          # toolbox bind-mount layout
cd "$ROOT"

REPO_URL="$(git remote get-url origin 2>/dev/null || echo "${ARGOCD_REPO_URL:-https://github.com/acme-takehome/quote-api.git}")"
IMAGE_REPO="${IMAGE_REPO:-ghcr.io/benhuhaudau/quote-api}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short=12 HEAD 2>/dev/null || echo latest)}"

echo "== [1/4] Installing/upgrading ArgoCD =="
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1 || true
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
  --set server.ingress.enabled=false \
  --set applicationSet.enabled=false \
  --set notifications.enabled=false \
  --set dex.enabled=false \
  --set redis.enabled=true \
  --set controller.repo.server.enabled=true >/dev/null

kubectl -n argocd rollout status deployment/argocd-server --timeout=300s

echo "== [2/4] Rendering ArgoCD Application (repo=$REPO_URL image=$IMAGE_REPO:$IMAGE_TAG) =="
    sed -e "s|__REPO_URL__|${REPO_URL}|g" \
    -e "s|__IMAGE_REPO__|${IMAGE_REPO}|g" \
    -e "s|__IMAGE_TAG__|${IMAGE_TAG}|g" \
    "$ROOT/config/argocd/application.yaml" \
    | kubectl apply -f -

echo "== [3/4] Waiting for app sync =="
u=0
until kubectl -n quote get deployment/quote-api >/dev/null 2>&1; do
  sleep 3; u=$((u+1)); [ "$u" -gt 60 ] && { echo "Timed out waiting for deployment (check argocd app logs)"; exit 1; }
done
kubectl -n quote rollout status deployment/quote-api --timeout=300s

echo "== [4/4] Smoke: curl from inside the cluster =="
for i in $(seq 1 30); do
  if bash "$(dirname "$0")/smoke.sh" quote quote-api; then
    echo "OK: service answering"
    break
  fi
  sleep 2
  [ "$i" = 30 ] && { echo "FAIL: service not reachable in-cluster"; exit 1; }
done

echo "ArgoCD UI: kubectl port-forward -n argocd svc/argocd-server 8082:443  (https://localhost:8082)"
