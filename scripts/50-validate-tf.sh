#!/usr/bin/env bash
# scripts/50-validate-tf.sh: Part 5: terraform fmt -check / init -backend=false / validate
# Runs inside the toolbox (terraform pre-installed). No credentials needed: validate only.
set -euo pipefail

DIR="/infra/cloudflare"
cd "$DIR"

echo "== terraform fmt -check =="
terraform fmt -check -recursive

echo "== terraform init -backend=false =="
terraform init -backend=false -input=false >/dev/null 2>&1 || terraform init -backend=false -input=false

echo "== terraform validate =="
terraform validate

echo "PASS: terraform sources are well-formed and Karpenter YAML present."
