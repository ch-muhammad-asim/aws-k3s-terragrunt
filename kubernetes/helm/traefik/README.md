# Traefik on K3s with Helm

This directory replaces K3s-bundled Traefik with the official Traefik Helm chart, pinned through a local wrapper chart.

## Pinned versions

| Component | Version |
|---|---:|
| K3s | `v1.36.4+k3s1` |
| Traefik Helm chart | `41.4.0` |
| Traefik Proxy | `v3.7.12` |
| whoami smoke-test image | `v1.12.0` |
| Local wrapper chart | `1.0.0` |

K3s configuration is centralized in `infrastructure/live/_common/k3s.hcl`, where bundled Traefik is disabled. Environment-specific leaves do not duplicate this platform setting.

## Prerequisites

From the repository root:

```bash
make kubeconfig ENV=dev REGION=us-east-1
export KUBECONFIG=~/.kube/k3s-dev-us-east-1.yaml
kubectl get nodes -o wide
helm version
```

## Inspect the official chart

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm repo list
helm search repo traefik/traefik
helm search repo traefik/traefik --versions | head -20
helm show chart traefik/traefik --version 41.4.0
helm show readme traefik/traefik --version 41.4.0
helm show values traefik/traefik --version 41.4.0
helm show all traefik/traefik --version 41.4.0
```

## Validate the wrapper chart

```bash
cd kubernetes/helm/traefik

helm dependency update .
helm dependency list .
helm lint . --values values.yaml
helm template traefik . --namespace traefik --values values.yaml >/tmp/traefik-rendered.yaml
```

Expected dependency:

```text
traefik  41.4.0  https://traefik.github.io/charts
```

## Install

Preferred platform workflow from the repository root:

```bash
make platform-install
```

Traefik only:

```bash
cd kubernetes/helm/traefik
./install.sh
```

Equivalent Helm command:

```bash
helm dependency update .
helm upgrade --install traefik . \
  --namespace traefik \
  --create-namespace \
  --values values.yaml \
  --wait \
  --timeout 10m
```

K3s ServiceLB remains enabled. The Traefik Service uses `LoadBalancer`, allowing the single-node K3s profile to expose ports 80/443 through the node/EIP.

## Verify

```bash
helm -n traefik list
helm -n traefik get metadata traefik
kubectl -n traefik get pods -o wide
kubectl -n traefik get deploy,svc
kubectl get ingressclass
kubectl describe ingressclass traefik
kubectl -n traefik logs deployment/traefik --tail=100
kubectl -n kube-system get pods | grep svclb || true
```

## End-to-end smoke test

```bash
cd kubernetes/helm/traefik
./test.sh
```

The test deploys pinned `traefik/whoami:v1.12.0`, creates an Ingress using the `traefik` class, and verifies HTTP routing through a temporary local port-forward.

For an EC2 Elastic IP test:

```bash
make outputs ENV=dev REGION=us-east-1
PUBLIC_IP=<public_ip_output>
curl -H 'Host: whoami.local' "http://${PUBLIC_IP}/"
```

## Optional HTTP -> HTTPS redirect

Enable only after TLS routes/certificates are ready:

```bash
helm upgrade --install traefik . \
  --namespace traefik \
  --values values.yaml \
  --values values-https-redirect.example.yaml \
  --wait \
  --timeout 10m
```

## Dashboard

Do not expose the insecure API. Use local port-forwarding:

```bash
kubectl -n traefik port-forward deployment/traefik 9000:8080
```

Open `http://127.0.0.1:9000/dashboard/`.

## Upgrade

```bash
helm repo update
helm search repo traefik/traefik --versions | head -20
```

Update `Chart.yaml` and `VERSIONS.md`, then lint/render before applying.

## Uninstall

```bash
./uninstall.sh
```
