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
| Amazon Linux | AL2023 current patched x86_64 AMI | `infrastructure/modules/ec2/main.tf` via AWS SSM public parameter |

## Ownership

- EC2 lifecycle and AWS compute settings are owned by `infrastructure/modules/ec2`.
- K3s installation/upgrades are owned independently by `infrastructure/modules/k3s` through AWS Systems Manager.
- The K3s version pin belongs in shared K3s configuration, not in the EC2 module or an environment-specific leaf.
- Helm application versions live in each wrapper `Chart.yaml`.

## Verify deployed versions

```bash
kubectl version
kubectl get nodes -o wide

make outputs ENV=dev REGION=us-east-1

helm -n traefik list
helm -n cert-manager list
helm -n argocd list
```

To verify K3s directly on the node:

```bash
make ssm ENV=dev REGION=us-east-1
k3s --version
```
