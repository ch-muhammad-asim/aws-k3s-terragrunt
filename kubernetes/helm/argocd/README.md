# Argo CD on K3s with Helm

This directory deploys Argo CD using the official `argo-cd` Helm chart as a pinned dependency.

## Pinned versions

| Component | Version |
|---|---:|
| K3s target | `v1.36.4+k3s1` |
| Traefik Helm chart | `41.4.0` |
| Traefik Proxy | `v3.7.12` |
| Argo CD Helm chart | `10.8.1` |
| Argo CD application | `v3.5.2` |
| Local wrapper chart | `1.0.0` |

`Chart.yaml` is the source of truth for Argo CD versions. K3s is pinned once in `infrastructure/live/_common/k3s.hcl`; environment/region leaf units consume that shared configuration.

## Prerequisites

From the repository root:

```bash
make kubeconfig ENV=dev REGION=us-east-1
export KUBECONFIG=~/.kube/k3s-dev-us-east-1.yaml
kubectl get nodes -o wide
kubectl -n traefik get pods,svc
kubectl get ingressclass traefik
```

## Validate the wrapper chart

```bash
cd kubernetes/helm/argocd

grep -E '^(version|appVersion):' Chart.yaml
grep -A4 '^dependencies:' Chart.yaml
helm dependency update .
helm dependency list .
helm lint . --values values.yaml
helm template argocd . --namespace argocd --values values.yaml >/tmp/argocd-rendered.yaml
```

Expected dependency:

```text
argo-cd  10.8.1  https://argoproj.github.io/argo-helm
```

## Install

From the repository root, the preferred path is:

```bash
make platform-install
```

For Argo CD only:

```bash
cd kubernetes/helm/argocd
./install.sh
```

Equivalent Helm command:

```bash
helm dependency update .
helm upgrade --install argocd . \
  --namespace argocd \
  --create-namespace \
  --values values.yaml \
  --wait \
  --timeout 10m
```

## Verify

```bash
helm -n argocd list
helm -n argocd get metadata argocd
kubectl -n argocd get pods -o wide
kubectl -n argocd get deployments,statefulsets,services
kubectl -n argocd rollout status deployment/argocd-server --timeout=5m
```

## Local UI access

The baseline does not expose Argo CD publicly:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Retrieve the initial password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Username: `admin`.

## Optional Traefik ingress

Point a DNS name at the EC2 Elastic IP, copy the example override and set the hostname:

```bash
cp values-traefik.example.yaml values-traefik.yaml
helm upgrade --install argocd . \
  --namespace argocd \
  --create-namespace \
  --values values.yaml \
  --values values-traefik.yaml \
  --wait \
  --timeout 10m
```

Verify:

```bash
kubectl -n argocd get ingress
kubectl -n traefik get pods,svc
kubectl get ingressclass traefik
```

For Internet-facing use, configure TLS with cert-manager rather than leaving HTTP enabled.

## Upgrade

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm search repo argo/argo-cd --versions | head -20
```

Update `Chart.yaml` and `VERSIONS.md` intentionally, then:

```bash
helm dependency update .
helm lint . --values values.yaml
helm template argocd . --namespace argocd --values values.yaml >/dev/null
helm upgrade --install argocd . --namespace argocd --values values.yaml --wait --timeout 10m
```

## Uninstall

```bash
./uninstall.sh
```
