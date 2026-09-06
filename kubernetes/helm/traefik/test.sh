#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NAMESPACE="${NAMESPACE:-traefik}"
LOCAL_PORT="${LOCAL_PORT:-18080}"
CLEANUP="${CLEANUP:-true}"

for cmd in kubectl curl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd is required" >&2; exit 1; }
done

kubectl -n "$NAMESPACE" rollout status deployment/traefik --timeout=5m
kubectl apply -f examples/whoami.yaml
kubectl -n traefik-test rollout status deployment/whoami --timeout=3m
kubectl -n traefik-test get ingress whoami

LOG_FILE="/tmp/traefik-port-forward.log"
kubectl -n "$NAMESPACE" port-forward svc/traefik "${LOCAL_PORT}:80" >"$LOG_FILE" 2>&1 &
PF_PID=$!
cleanup() {
  kill "$PF_PID" >/dev/null 2>&1 || true
  if [[ "$CLEANUP" == "true" ]]; then
    kubectl delete namespace traefik-test --wait=false >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

for _ in $(seq 1 20); do
  if curl -fsS -H 'Host: whoami.local' "http://127.0.0.1:${LOCAL_PORT}/" >/tmp/traefik-whoami-response.txt; then
    cat /tmp/traefik-whoami-response.txt
    echo "Traefik ingress smoke test: PASS"
    exit 0
  fi
  sleep 1
done

echo "Traefik ingress smoke test: FAIL" >&2
cat "$LOG_FILE" >&2 || true
exit 1
