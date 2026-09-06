#!/usr/bin/env bash
set -euo pipefail

for cmd in aws terragrunt git sed; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd is required" >&2; exit 1; }
done

ROOT="$(git rev-parse --show-toplevel)"
ENVIRONMENT="${ENV:-dev}"
REGION="${REGION:-us-east-1}"
K3S_DIR="${ROOT}/infrastructure/live/${ENVIRONMENT}/${REGION}/k3s"
KUBECONFIG_FILE="${KUBECONFIG_FILE:-${HOME}/.kube/k3s-${ENVIRONMENT}-${REGION}.yaml}"

[[ -d "$K3S_DIR" ]] || {
  echo "ERROR: stack not found: $K3S_DIR" >&2
  echo "Create infrastructure/live/${ENVIRONMENT}/${REGION} first." >&2
  exit 1
}

INSTANCE_ID="$(cd "$K3S_DIR" && terragrunt output -raw instance_id)"
PUBLIC_IP="$(cd "$K3S_DIR" && terragrunt output -raw public_ip)"

CMD_ID="$(aws ssm send-command \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["sudo cat /etc/rancher/k3s/k3s.yaml"]' \
  --query 'Command.CommandId' \
  --output text)"

status="Pending"
for _ in $(seq 1 60); do
  status="$(aws ssm get-command-invocation \
    --region "$REGION" \
    --command-id "$CMD_ID" \
    --instance-id "$INSTANCE_ID" \
    --query Status \
    --output text 2>/dev/null || true)"

  case "$status" in
    Success) break ;;
    Failed|Cancelled|TimedOut)
      echo "ERROR: SSM command finished with status: $status" >&2
      exit 1
      ;;
  esac

  sleep 2
done

[[ "$status" == "Success" ]] || {
  echo "ERROR: timed out waiting for kubeconfig from SSM" >&2
  exit 1
}

mkdir -p "$(dirname "$KUBECONFIG_FILE")"
aws ssm get-command-invocation \
  --region "$REGION" \
  --command-id "$CMD_ID" \
  --instance-id "$INSTANCE_ID" \
  --query StandardOutputContent \
  --output text \
  | sed "s/127.0.0.1/${PUBLIC_IP}/" \
  > "$KUBECONFIG_FILE"

chmod 600 "$KUBECONFIG_FILE"

printf 'Kubeconfig: %s\n' "$KUBECONFIG_FILE"
printf 'Use: export KUBECONFIG=%q\n' "$KUBECONFIG_FILE"
