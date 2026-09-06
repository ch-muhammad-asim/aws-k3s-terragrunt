# cert-manager on K3s with Helm

This directory deploys cert-manager from its official Helm chart as a pinned dependency and includes self-contained validation plus Cloudflare DNS-01 / Let's Encrypt examples.

## Pinned versions

| Component | Version |
|---|---:|
| K3s | `v1.36.4+k3s1` |
| cert-manager Helm chart | `v1.21.1` |
| cert-manager application | `v1.21.1` |
| Local wrapper chart | `1.0.0` |

The official chart is published at `oci://quay.io/jetstack/charts/cert-manager`.

## CRD configuration

The legacy setting `installCRDs: true` is deprecated. This repository uses:

```yaml
crds:
  enabled: true
  keep: true
```

`keep: true` prevents Helm uninstall from deleting the CRDs and cascading deletion of cert-manager custom resources.

## Prerequisites

From the repository root:

```bash
make kubeconfig ENV=dev REGION=us-east-1
export KUBECONFIG=~/.kube/k3s-dev-us-east-1.yaml
kubectl get nodes -o wide
helm version
```

## Inspect the official OCI chart

```bash
helm show chart oci://quay.io/jetstack/charts/cert-manager --version v1.21.1
helm show readme oci://quay.io/jetstack/charts/cert-manager --version v1.21.1
helm show values oci://quay.io/jetstack/charts/cert-manager --version v1.21.1
helm show all oci://quay.io/jetstack/charts/cert-manager --version v1.21.1
```

## Validate the wrapper chart

```bash
cd kubernetes/helm/cert-manager
helm dependency update .
helm dependency list .
helm lint . --values values.yaml
helm template cert-manager . --namespace cert-manager --values values.yaml >/tmp/cert-manager-rendered.yaml
```

## Install

Preferred platform workflow from the repository root:

```bash
make platform-install
```

cert-manager only:

```bash
cd kubernetes/helm/cert-manager
./install.sh
```

Equivalent official OCI install for comparison/debugging:

```bash
helm upgrade --install cert-manager \
  oci://quay.io/jetstack/charts/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.21.1 \
  --set crds.enabled=true \
  --set crds.keep=true \
  --wait \
  --timeout 10m
```

## Verify

```bash
helm -n cert-manager list
helm -n cert-manager get metadata cert-manager
kubectl -n cert-manager get pods -o wide
kubectl -n cert-manager get deploy,svc
kubectl get crd | grep cert-manager.io
kubectl api-resources --api-group=cert-manager.io
kubectl -n cert-manager logs deployment/cert-manager --tail=100
kubectl -n cert-manager logs deployment/cert-manager-webhook --tail=100
```

## Functional smoke test

The test needs no public DNS or Let's Encrypt. It creates a temporary self-signed Issuer and Certificate and verifies a TLS Secret is produced.

```bash
cd kubernetes/helm/cert-manager
./test.sh
```

## Cloudflare DNS-01 + Let's Encrypt

Never commit a real Cloudflare token. Create it directly in the cluster:

```bash
export CLOUDFLARE_API_TOKEN='<token>'
kubectl -n cert-manager create secret generic cloudflare-api-token \
  --from-literal=api-token="$CLOUDFLARE_API_TOKEN"
```

Use staging first:

```bash
kubectl apply -f examples/clusterissuer-staging.example.yaml
kubectl wait --for=condition=Ready clusterissuer/letsencrypt-staging --timeout=2m
kubectl describe clusterissuer letsencrypt-staging
```

After staging succeeds, configure production:

```bash
kubectl apply -f examples/clusterissuer-production.example.yaml
kubectl wait --for=condition=Ready clusterissuer/letsencrypt-production --timeout=2m
kubectl describe clusterissuer letsencrypt-production
```

Apply a certificate and inspect the ACME workflow:

```bash
kubectl apply -f examples/certificate.example.yaml
kubectl -n default get certificate,certificaterequest
kubectl -n default get order,challenge
kubectl -n default describe certificate example-com
```

For Traefik TLS, edit and apply `examples/ingress-tls.example.yaml` after the whoami Service exists.

## Troubleshooting

```bash
kubectl get clusterissuers
kubectl describe clusterissuer letsencrypt-production
kubectl -A get certificate,certificaterequest
kubectl -A get order,challenge
kubectl -n cert-manager get events --sort-by=.lastTimestamp
kubectl -n cert-manager logs deployment/cert-manager --tail=200
```

If `cmctl` is installed:

```bash
cmctl check api
cmctl renew -n default example-com
```

## Upgrade

Update the pinned version in `Chart.yaml` and `VERSIONS.md` intentionally, then dependency-update, lint and render before applying.

## Uninstall

```bash
./uninstall.sh
```

CRDs remain because `crds.keep=true`.
