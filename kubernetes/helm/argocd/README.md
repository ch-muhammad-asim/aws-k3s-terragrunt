# Argo CD on K3s with Helm

This directory deploys Argo CD using the **official `argo-cd` Helm chart** as a pinned dependency.

## Pinned versions

| Component | Version |
|---|---:|
| K3s target | `v1.36.4+k3s1` |
| Traefik Helm chart | `41.4.0` |
| Traefik Proxy | `v3.7.12` |
| Argo CD Helm chart | `10.8.1` |
| Argo CD application | `v3.5.2` |
| Local wrapper chart | `1.0.0` |

`Chart.yaml` is the source of truth for the Argo CD chart/application versions. The K3s version is pinned in `terragrunt/env/dev/region/us-east-1/k3s/terragrunt.hcl`.

## Prerequisites

Make sure your kubeconfig points to the K3s cluster and that the Helm-managed Traefik controller is installed first:

```bash
export KUBECONFIG=~/.kube/k3s-dev.yaml
kubectl get nodes -o wide
kubectl version
helm version
kubectl -n traefik get pods,svc
kubectl get ingressclass traefik
```

## Validate chart versions before deployment

```bash
cd kubernetes/helm/argocd

grep -E '^(version|appVersion):' Chart.yaml
grep -A4 '^dependencies:' Chart.yaml
helm dependency update .
helm dependency list .
```

Expected dependency:

```text
argo-cd  10.8.1  https://argoproj.github.io/argo-helm
```

## Install Argo CD

Recommended scripted deployment:

```bash
./install.sh
```

Equivalent manual commands:

```bash
helm dependency update .
helm lint . --values values.yaml

helm template argocd . \
  --namespace argocd \
  --values values.yaml \
  >/tmp/argocd-rendered.yaml

helm upgrade --install argocd . \
  --namespace argocd \
  --create-namespace \
  --values values.yaml \
  --wait \
  --timeout 10m
```

Verify:

```bash
helm -n argocd list
helm -n argocd get metadata argocd
kubectl -n argocd get pods -o wide
kubectl -n argocd get deployments,statefulsets,services
kubectl -n argocd rollout status deployment/argocd-server --timeout=5m
```

## Access the UI locally

The default values intentionally do **not** expose Argo CD publicly. Use port-forwarding first:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Open `http://localhost:8080`.

Get the generated initial administrator password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Username:

```text
admin
```

After you configure a permanent login/SSO method, remove the initial admin secret if your security policy requires it.

## Optional public access through Traefik

1. Point a DNS record such as `argocd.example.com` to the EC2 Elastic IP.
2. Copy the example override and replace the hostname:

```bash
cp values-traefik.example.yaml values-traefik.yaml
```

3. Deploy with both files:

```bash
helm upgrade --install argocd . \
  --namespace argocd \
  --create-namespace \
  --values values.yaml \
  --values values-traefik.yaml \
  --wait \
  --timeout 10m
```

Check the ingress and the Helm-managed Traefik controller:

```bash
kubectl -n argocd get ingress
kubectl -n traefik get pods,svc
kubectl get ingressclass traefik
```

For Internet-facing usage, configure TLS with cert-manager rather than leaving HTTP enabled.

## Upgrade later

Do not use an unpinned `latest` chart in production. To upgrade intentionally:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm search repo argo/argo-cd --versions | head
```

Then update the dependency `version` and `appVersion` in `Chart.yaml`, run:

```bash
helm dependency update .
helm lint . --values values.yaml
helm template argocd . --namespace argocd --values values.yaml >/dev/null
helm upgrade --install argocd . --namespace argocd --values values.yaml --wait --timeout 10m
```

Commit the version change so the deployed version remains auditable.

## Uninstall

```bash
./uninstall.sh
```
