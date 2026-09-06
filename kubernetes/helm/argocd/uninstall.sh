#!/usr/bin/env bash
set -euo pipefail

RELEASE_NAME="${ARGOCD_RELEASE_NAME:-argocd}"
NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

helm uninstall "$RELEASE_NAME" --namespace "$NAMESPACE"

echo "Argo CD release removed."
echo "Namespace was intentionally kept. Remove it explicitly with:"
echo "  kubectl delete namespace ${NAMESPACE}"
