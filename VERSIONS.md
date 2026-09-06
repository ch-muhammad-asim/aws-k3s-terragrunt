# Version matrix

Runtime/platform versions are intentionally pinned so a rebuild does not silently change behavior. Upstream versions below were checked on **2026-09-06**.

| Component | Version / constraint | Source of truth |
|---|---|---|
| K3s | `v1.36.4+k3s1` | `infrastructure/live/_common/k3s.hcl` |
| Traefik Helm chart | `41.4.0` | `kubernetes/helm/traefik/Chart.yaml` |
| Traefik Proxy | `v3.7.12` | `kubernetes/helm/traefik/Chart.yaml` |
| Traefik wrapper chart | `1.0.0` | `kubernetes/helm/traefik/Chart.yaml` |
| Traefik whoami smoke test | `v1.12.0` | `kubernetes/helm/traefik/examples/whoami.yaml` |
| cert-manager Helm chart | `v1.21.1` | `kubernetes/helm/cert-manager/Chart.yaml` |
| cert-manager application | `v1.21.1` | `kubernetes/helm/cert-manager/Chart.yaml` |
| cert-manager wrapper chart | `1.0.0` | `kubernetes/helm/cert-manager/Chart.yaml` |
| Argo CD Helm chart | `10.8.1` | `kubernetes/helm/argocd/Chart.yaml` |
| Argo CD application | `v3.5.2` | `kubernetes/helm/argocd/Chart.yaml` |
| Argo CD wrapper chart | `1.0.0` | `kubernetes/helm/argocd/Chart.yaml` |
| Terraform CLI | `>= 1.8.0` | `infrastructure/modules/*/versions.tf` |
| AWS provider | `>= 5.0, < 7.0` | `infrastructure/modules/*/versions.tf` |
| Amazon Linux | AL2023 current patched x86_64 AMI | AWS SSM public parameter in `infrastructure/modules/k3s-ec2/main.tf` |

## Version ownership

Platform defaults belong in shared component configuration, not an environment-specific leaf. K3s therefore has one version pin under `infrastructure/live/_common/k3s.hcl`, while Helm application versions live in each wrapper `Chart.yaml`.

Environment/region leaves consume those pins and contain only wiring/overrides.

## Platform relationship

K3s is installed with bundled Traefik disabled. The separately managed Traefik Helm release owns the `traefik` IngressClass and its LoadBalancer Service. cert-manager manages TLS/ACME resources. Argo CD runs on top of that ingress/certificate layer.

## Verify deployed versions

```bash
kubectl version
kubectl get nodes -o wide

helm -n traefik list
helm -n traefik get metadata traefik
helm -n cert-manager list
helm -n cert-manager get metadata cert-manager
helm -n argocd list
helm -n argocd get metadata argocd

kubectl -n traefik get pods -o wide
kubectl -n cert-manager get pods -o wide
kubectl -n argocd get pods -o wide
```

For the EC2 node itself:

```bash
make ssm ENV=dev REGION=us-east-1
k3s --version
```
