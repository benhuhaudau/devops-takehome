#!/usr/bin/env bash
# scripts/00-bootstrap.sh: runs as the compose cluster-bootstrap service.
# Creates the k3d cluster (1 server + 4 agents, k8s 1.35) if missing,
# then applies the PROVIDED troubleshoot/prepare.sh nodepool simulation.
# Idempotent. Uses the Docker socket bound at /var/run/docker.sock.
set -euo pipefail

CLUSTER=takehome

if ! k3d cluster get "$CLUSTER" >/dev/null 2>&1; then
  echo "Creating k3d cluster '$CLUSTER' (1 server + 4 agents)..."
  k3d cluster create "$CLUSTER" \
    --servers 1 --agents 4 \
    -p "8080:80@loadbalancer" -p "8443:443@loadbalancer" \
    --wait
else
  echo "Cluster '$CLUSTER' already exists: skip create"
fi

# Containers reach the cluster serverlb via host.docker.internal (port is
# published on the host). The k3s cert has no SAN for that name, so we pin
# tls-server-name: kubernetes (always present in the server cert).
echo "Writing kubeconfig for in-container use..."
k3d kubeconfig get "$CLUSTER" \
  | sed -E 's|https://[0-9.]+:([0-9]+)|https://host.docker.internal:\1|' \
  > "$KUBECONFIG"
kubectl config view --kubeconfig "$KUBECONFIG" --raw -o json \
  | jq '.clusters[0].cluster["tls-server-name"] = "kubernetes"' \
  > "$KUBECONFIG.tmp"
install -m 600 "$KUBECONFIG.tmp" "$KUBECONFIG"

echo "Waiting for all nodes to be Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo "Applying nodepool simulation (provided troubleshoot/prepare.sh)..."
sh /troubleshoot/prepare.sh

echo "Bootstrap done."
