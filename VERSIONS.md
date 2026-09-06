# Version matrix

The deployment intentionally pins runtime/platform versions so a rebuild does not silently change behavior.

| Component | Version / constraint | Where configured |
|---|---|---|
| K3s | `v1.36.4+k3s1` | `terragrunt/env/dev/region/us-east-1/k3s/terragrunt.hcl` |
| Argo CD Helm chart | `10.8.1` | `kubernetes/helm/argocd/Chart.yaml` |
| Argo CD application | `v3.5.2` | `kubernetes/helm/argocd/Chart.yaml` |
| Argo CD wrapper chart | `1.0.0` | `kubernetes/helm/argocd/Chart.yaml` |
| Terraform CLI | `>= 1.8.0` | `terraform/modules/*/versions.tf` |
| AWS provider | `>= 5.0, < 7.0` | `terraform/modules/*/versions.tf` |
| Amazon Linux | AL2023 current patched x86_64 AMI | resolved from AWS SSM public parameter in `terraform/modules/k3s-ec2/main.tf` |

## Why K3s is pinned

The previous configuration used the moving `stable` channel. That means rebuilding the same Terraform later could install a different K3s release. It now uses `INSTALL_K3S_VERSION` with `v1.36.4+k3s1`, making the installed K3s version explicit and reproducible.

## Version checks after deployment

```bash
kubectl version
kubectl get nodes -o wide

# On the EC2 node through SSM:
k3s --version

# Argo CD chart and application objects:
helm -n argocd list
helm -n argocd get metadata argocd
kubectl -n argocd get pods -o wide
```
