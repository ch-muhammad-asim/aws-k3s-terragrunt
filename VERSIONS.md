# Version matrix

The deployment intentionally pins runtime/platform versions so a rebuild does not silently change behavior. Upstream release versions below were checked on **2026-09-06**.

| Component | Version / constraint | Where configured |
|---|---|---|
| K3s | `v1.36.4+k3s1` | `terragrunt/env/dev/region/us-east-1/k3s/terragrunt.hcl` |
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
| Terraform CLI | `>= 1.8.0` | `terraform/modules/*/versions.tf` |
| AWS provider | `>= 5.0, < 7.0` | `terraform/modules/*/versions.tf` |
| Amazon Linux | AL2023 current patched x86_64 AMI | resolved from AWS SSM public parameter in `terraform/modules/k3s-ec2/main.tf` |

## Platform relationship

K3s is installed with its bundled Traefik disabled. The separately managed Traefik Helm chart owns the `traefik` IngressClass and the LoadBalancer Service on ports 80/443. cert-manager is installed independently and can issue TLS Secrets used by Traefik Ingress objects. Argo CD can then be exposed through that ingress/TLS stack.

## Why K3s is pinned

The previous configuration used the moving `stable` channel. That means rebuilding the same Terraform later could install a different K3s release. It now uses `INSTALL_K3S_VERSION` with `v1.36.4+k3s1`, making the installed K3s version explicit and reproducible.

## Version checks after deployment

```bash
kubectl version
kubectl get nodes -o wide

# On the EC2 node through SSM:
k3s --version

# Helm releases:
helm -n traefik list
helm -n traefik get metadata traefik
helm -n cert-manager list
helm -n cert-manager get metadata cert-manager
helm -n argocd list
helm -n argocd get metadata argocd

# Workloads:
kubectl -n traefik get pods -o wide
kubectl -n cert-manager get pods -o wide
kubectl -n argocd get pods -o wide
```
