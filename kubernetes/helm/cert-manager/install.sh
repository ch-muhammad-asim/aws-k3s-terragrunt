#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RELEASE_NAME="${RELEASE_NAME:-cert-manager}"
NAMESPACE="${NAMESPACE:-cert-manager}"
VALUES_FILE="${VALUES_FILE:-values.yaml}"
TIMEOUT="${TIMEOUT:-10m}"

for cmd in helm kubectl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd is required" >&2; exit 1; }
done

kubectl cluster-info >/dev/null

echo "==> Updating pinned cert-manager dependency"
helm dependency update .
helm dependency list .

echo "==> Linting and rendering chart"
helm lint . --values "$VALUES_FILE"
helm template "$RELEASE_NAME" . \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE" \
  >/tmp/cert-manager-rendered.yaml

echo "==> Installing cert-manager"
helm upgrade --install "$RELEASE_NAME" . \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$VALUES_FILE" \
  --wait \
  --timeout "$TIMEOUT"

echo "==> Waiting for cert-manager components"
kubectl -n "$NAMESPACE" rollout status deployment/cert-manager --timeout=5m
kubectl -n "$NAMESPACE" rollout status deployment/cert-manager-webhook --timeout=5m
kubectl -n "$NAMESPACE" rollout status deployment/cert-manager-cainjector --timeout=5m
kubectl -n "$NAMESPACE" get pods -o wide
kubectl get crd certificates.cert-manager.io clusterissuers.cert-manager.io
helm -n "$NAMESPACE" list
