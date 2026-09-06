#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NAMESPACE="${NAMESPACE:-cert-manager}"
CLEANUP="${CLEANUP:-true}"

command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl is required" >&2; exit 1; }

kubectl -n "$NAMESPACE" rollout status deployment/cert-manager --timeout=5m
kubectl -n "$NAMESPACE" rollout status deployment/cert-manager-webhook --timeout=5m
kubectl -n "$NAMESPACE" rollout status deployment/cert-manager-cainjector --timeout=5m

kubectl apply -f examples/selfsigned-smoke-test.yaml
kubectl -n cert-manager-test wait \
  --for=condition=Ready \
  certificate/cert-manager-smoke-test \
  --timeout=2m

kubectl -n cert-manager-test get certificate cert-manager-smoke-test
kubectl -n cert-manager-test get secret cert-manager-smoke-test-tls

echo "cert-manager self-signed certificate smoke test: PASS"

if [[ "$CLEANUP" == "true" ]]; then
  kubectl delete namespace cert-manager-test --wait=false >/dev/null
fi
