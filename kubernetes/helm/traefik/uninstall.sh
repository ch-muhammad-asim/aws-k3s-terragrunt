#!/usr/bin/env bash
set -euo pipefail

RELEASE_NAME="${RELEASE_NAME:-traefik}"
NAMESPACE="${NAMESPACE:-traefik}"

helm uninstall "$RELEASE_NAME" --namespace "$NAMESPACE" --wait

echo "Traefik release removed. Test resources, if retained, can be removed with:"
echo "  kubectl delete namespace traefik-test"
