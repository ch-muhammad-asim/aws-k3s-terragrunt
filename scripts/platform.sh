#!/usr/bin/env bash
set -euo pipefail

command -v git >/dev/null 2>&1 || { echo "ERROR: git is required" >&2; exit 1; }

ROOT="$(git rev-parse --show-toplevel)"
HELM_ROOT="${ROOT}/kubernetes/helm"
ACTION="${1:-install}"

run_component() {
  local component="$1"
  local script="$2"
  echo "==> ${component}: ${script}"
  "${HELM_ROOT}/${component}/${script}"
}

case "$ACTION" in
  install)
    run_component traefik install.sh
    run_component cert-manager install.sh
    run_component argocd install.sh
    ;;
  test)
    run_component traefik test.sh
    run_component cert-manager test.sh
    kubectl -n argocd rollout status deployment/argocd-server --timeout=5m
    kubectl -n argocd get pods -o wide
    ;;
  uninstall)
    run_component argocd uninstall.sh
    run_component cert-manager uninstall.sh
    run_component traefik uninstall.sh
    ;;
  *)
    echo "Usage: $0 {install|test|uninstall}" >&2
    exit 2
    ;;
esac
