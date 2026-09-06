# Traefik on K3s with Helm

This directory replaces the K3s-bundled Traefik with the **official Traefik Helm chart**, pinned through a local wrapper chart.

## Pinned versions

| Component | Version |
|---|---:|
| K3s | `v1.36.4+k3s1` |
| Traefik Helm chart | `41.4.0` |
| Traefik Proxy | `v3.7.12` |
| whoami smoke-test image | `v1.12.0` |
| Local wrapper chart | `1.0.0` |

The chart version is pinned in `Chart.yaml`. The upstream Traefik chart `41.4.0` uses Traefik Proxy `v3.7.12`.

## Important K3s correction

The Terragrunt K3s unit sets:

```hcl
enable_traefik = false
```

Do not install this Helm release while the bundled K3s Traefik is enabled. Running two Traefik controllers can create conflicting IngressClasses, Services and host ports.

If this cluster was already created with bundled Traefik enabled, inspect `terragrunt plan` carefully: the repository uses `user_data_replace_on_change = true`, so changing the K3s bootstrap flags can replace the EC2 instance.

K3s ServiceLB remains enabled. The Traefik Helm Service uses `type: LoadBalancer`, so on this single-node cluster K3s ServiceLB exposes ports 80/443 through the EC2 node/EIP.

## Prerequisites

```bash
export KUBECONFIG=~/.kube/k3s-dev.yaml
kubectl get nodes -o wide
kubectl version
helm version
```

## Inspect the official chart

These are the modern equivalents of the commands from the older Traefik repository:

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

grep -E '^(version|appVersion):' Chart.yaml
grep -A5 '^dependencies:' Chart.yaml
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

Recommended:

```bash
./install.sh
```

Equivalent manual install:

```bash
helm dependency update .
helm upgrade --install traefik . \
  --namespace traefik \
  --create-namespace \
  --values values.yaml \
  --wait \
  --timeout 10m
```

Direct upstream-chart equivalent, useful only for a quick comparison/test:

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --version 41.4.0 \
  --set ingressClass.enabled=true \
  --set ingressClass.isDefaultClass=true \
  --set service.spec.type=LoadBalancer \
  --wait \
  --timeout 10m
```

Prefer the wrapper chart in this repository so the exact chart version and K3s-specific values stay in Git.

## Verify

```bash
helm -n traefik list
helm -n traefik get metadata traefik
kubectl -n traefik get pods -o wide
kubectl -n traefik get deploy,svc
kubectl get ingressclass
kubectl describe ingressclass traefik
kubectl -n traefik logs deployment/traefik --tail=100
```

Check the LoadBalancer service:

```bash
kubectl -n traefik get svc traefik -o wide
kubectl -n kube-system get pods | grep svclb || true
```

## End-to-end ingress smoke test

The test uses the pinned `traefik/whoami:v1.12.0` image and routes `Host: whoami.local` through the Traefik Service.

```bash
./test.sh
```

Manual version:

```bash
kubectl apply -f examples/whoami.yaml
kubectl -n traefik-test rollout status deployment/whoami
kubectl -n traefik-test get ingress

kubectl -n traefik port-forward svc/traefik 18080:80
# In another terminal:
curl -H 'Host: whoami.local' http://127.0.0.1:18080/
```

To test through the EC2 Elastic IP:

```bash
PUBLIC_IP=<EC2_ELASTIC_IP>
curl -H 'Host: whoami.local' "http://${PUBLIC_IP}/"
```

## Optional HTTP to HTTPS redirect

Do not enable a global HTTPS redirect until your TLS certificates/routes are ready.

```bash
helm upgrade --install traefik . \
  --namespace traefik \
  --values values.yaml \
  --values values-https-redirect.example.yaml \
  --wait \
  --timeout 10m
```

## Dashboard access

The dashboard IngressRoute is intentionally disabled. For troubleshooting, use local port-forwarding rather than `--api.insecure=true`:

```bash
kubectl -n traefik port-forward deployment/traefik 9000:8080
```

Then visit `http://127.0.0.1:9000/dashboard/`.

## Upgrade later

Check upstream releases and chart versions first:

```bash
helm repo update
helm search repo traefik/traefik --versions | head -20
```

Then update both `dependencies[].version` and `appVersion` in `Chart.yaml`, update the version matrix, render/lint, and commit the change.

## Uninstall

```bash
./uninstall.sh
```
