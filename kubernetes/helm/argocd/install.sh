#!/usr/bin/env bash
set -euo pipefail

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_NAME="${ARGOCD_RELEASE_NAME:-argocd}"
NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

ARGOCD_HELM_CHART_VERSION="10.8.1"
ARGOCD_APP_VERSION="v3.5.2"
K3S_VERSION="v1.36.4+k3s1"

for cmd in kubectl helm; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: $cmd is required but was not found in PATH." >&2
    exit 1
  }
done

kubectl cluster-info >/dev/null

echo "Installing versions:"
echo "  K3s target:          ${K3S_VERSION}"
echo "  Argo CD Helm chart: ${ARGOCD_HELM_CHART_VERSION}"
echo "  Argo CD app:        ${ARGOCD_APP_VERSION}"

echo "Updating pinned Helm dependency..."
helm dependency update "$CHART_DIR"

echo "Rendering chart as a preflight validation..."
helm template "$RELEASE_NAME" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --values "$CHART_DIR/values.yaml" \
  >/dev/null

echo "Installing/upgrading Argo CD..."
helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$CHART_DIR/values.yaml" \
  --wait \
  --timeout 10m

echo
echo "Argo CD installed."
echo "Check pods:"
echo "  kubectl -n ${NAMESPACE} get pods -o wide"
echo "Initial admin password:"
echo "  kubectl -n ${NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
echo "Local UI access:"
echo "  kubectl -n ${NAMESPACE} port-forward svc/argocd-server 8080:80"
echo "Then open: http://localhost:8080"
