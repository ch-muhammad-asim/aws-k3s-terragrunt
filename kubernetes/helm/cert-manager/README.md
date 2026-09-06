# cert-manager on K3s with Helm

This directory deploys **cert-manager** from its official Helm chart as a pinned dependency. It also contains safe smoke tests and Cloudflare DNS-01 / Let's Encrypt examples based on the older `traefik-cert-manager` repository, updated for the current chart.

## Pinned versions

| Component | Version |
|---|---:|
| K3s | `v1.36.4+k3s1` |
| cert-manager Helm chart | `v1.21.1` |
| cert-manager application | `v1.21.1` |
| Local wrapper chart | `1.0.0` |

The upstream release publishes the official chart to `oci://quay.io/jetstack/charts/cert-manager`.

## Important correction from older values

Do not use the old setting:

```yaml
installCRDs: true
```

It is deprecated. The current chart uses:

```yaml
crds:
  enabled: true
  keep: true
```

`keep: true` prevents Helm uninstall from deleting the CRDs and causing Kubernetes garbage collection of Certificates, Issuers, ClusterIssuers and related resources.

## Prerequisites

```bash
export KUBECONFIG=~/.kube/k3s-dev.yaml
kubectl get nodes -o wide
kubectl version
helm version
```

## Inspect the official OCI chart

```bash
helm show chart oci://quay.io/jetstack/charts/cert-manager --version v1.21.1
helm show readme oci://quay.io/jetstack/charts/cert-manager --version v1.21.1
helm show values oci://quay.io/jetstack/charts/cert-manager --version v1.21.1
helm show all oci://quay.io/jetstack/charts/cert-manager --version v1.21.1
helm pull oci://quay.io/jetstack/charts/cert-manager --version v1.21.1
```

## Validate the wrapper chart

```bash
cd kubernetes/helm/cert-manager

grep -E '^(version|appVersion):' Chart.yaml
grep -A5 '^dependencies:' Chart.yaml
helm dependency update .
helm dependency list .
helm lint . --values values.yaml
helm template cert-manager . --namespace cert-manager --values values.yaml >/tmp/cert-manager-rendered.yaml
```

Expected dependency:

```text
cert-manager  v1.21.1  oci://quay.io/jetstack/charts
```

## Install

Recommended:

```bash
./install.sh
```

Equivalent manual install:

```bash
helm dependency update .
helm upgrade --install cert-manager . \
  --namespace cert-manager \
  --create-namespace \
  --values values.yaml \
  --wait \
  --timeout 10m
```

Direct official OCI install, useful for comparison/debugging:

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

## Self-contained functional smoke test

This does not require public DNS or Let's Encrypt. It creates a temporary self-signed Issuer and Certificate and verifies that a TLS Secret is produced.

```bash
./test.sh
```

Manual version:

```bash
kubectl apply -f examples/selfsigned-smoke-test.yaml
kubectl -n cert-manager-test wait --for=condition=Ready certificate/cert-manager-smoke-test --timeout=2m
kubectl -n cert-manager-test get certificate
kubectl -n cert-manager-test get secret cert-manager-smoke-test-tls
kubectl delete namespace cert-manager-test
```

## Cloudflare DNS-01 + Let's Encrypt

The examples never contain a real token. Keep the Cloudflare token out of Git.

### 1. Create the Cloudflare API token Secret

Preferred command:

```bash
export CLOUDFLARE_API_TOKEN='<token>'
kubectl -n cert-manager create secret generic cloudflare-api-token \
  --from-literal=api-token="$CLOUDFLARE_API_TOKEN"
```

Or review the placeholder manifest:

```bash
cat examples/cloudflare-secret.example.yaml
```

### 2. Configure staging first

Edit the email and DNS zone in `examples/clusterissuer-staging.example.yaml`, then:

```bash
kubectl apply -f examples/clusterissuer-staging.example.yaml
kubectl wait --for=condition=Ready clusterissuer/letsencrypt-staging --timeout=2m
kubectl describe clusterissuer letsencrypt-staging
```

### 3. Test a staging certificate

Edit `examples/certificate.example.yaml` to reference `letsencrypt-staging` while testing, then:

```bash
kubectl apply -f examples/certificate.example.yaml
kubectl -n default get certificate,certificaterequest
kubectl -n default get order,challenge
kubectl -n default describe certificate example-com
```

### 4. Configure production

After staging works, edit and apply:

```bash
kubectl apply -f examples/clusterissuer-production.example.yaml
kubectl wait --for=condition=Ready clusterissuer/letsencrypt-production --timeout=2m
kubectl describe clusterissuer letsencrypt-production
```

Then switch the Certificate `issuerRef` to `letsencrypt-production` and apply it.

### 5. Traefik TLS Ingress

Once the Traefik whoami example exists, edit the hostname in `examples/ingress-tls.example.yaml` and apply:

```bash
kubectl apply -f examples/ingress-tls.example.yaml
kubectl -n traefik-test get ingress
kubectl -n traefik-test get certificate,certificaterequest,order,challenge
kubectl -n traefik-test get secret whoami-example-com-tls
```

For DNS-01, your DNS A/AAAA record still needs to point clients to the EC2 Elastic IP for real browser access; ACME DNS validation itself is performed through the Cloudflare DNS API.

## Troubleshooting

```bash
kubectl get clusterissuers
kubectl describe clusterissuer letsencrypt-production
kubectl -A get certificate,certificaterequest
kubectl -A get order,challenge
kubectl -n cert-manager get events --sort-by=.lastTimestamp
kubectl -n cert-manager logs deployment/cert-manager --tail=200
```

If `cmctl` is installed, check the API and renew a certificate intentionally:

```bash
cmctl check api
cmctl renew -n default example-com
```

## Upgrade later

Check the cert-manager upstream release first, then intentionally update the pinned version in `Chart.yaml` and `VERSIONS.md`.

```bash
helm show chart oci://quay.io/jetstack/charts/cert-manager --version v1.21.1
helm dependency update .
helm lint . --values values.yaml
helm template cert-manager . --namespace cert-manager --values values.yaml >/dev/null
```

## Uninstall

```bash
./uninstall.sh
```

The CRDs remain because `crds.keep=true`. This is deliberate.
