#!/usr/bin/env bash
set -euo pipefail

RELEASE_NAME="${RELEASE_NAME:-cert-manager}"
NAMESPACE="${NAMESPACE:-cert-manager}"

helm uninstall "$RELEASE_NAME" --namespace "$NAMESPACE" --wait

cat <<'EOF'
cert-manager release removed.

The CRDs are intentionally retained because values.yaml sets crds.keep=true.
This protects Certificate/Issuer resources from accidental garbage collection.
If you truly intend to remove the CRDs and all cert-manager custom resources,
review the objects first and delete the CRDs manually.
EOF
