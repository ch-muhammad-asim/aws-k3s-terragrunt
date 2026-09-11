# Version matrix

Runtime/platform versions are intentionally pinned so a rebuild does not silently change behavior.

| Component | Version / constraint | Source of truth |
|---|---|---|
| K3s | `v1.36.4+k3s1` | `infrastructure/live/_common/k3s.hcl` |
| HashiCorp Helm provider | `3.2.0` | `infrastructure/modules/helm-release/versions.tf` |
| Traefik Helm chart | `41.4.0` | `infrastructure/live/_common/traefik.hcl` |
| Traefik Proxy | `v3.7.12` | upstream chart `41.4.0` |
| Traefik whoami example image | `v1.12.0` | `kubernetes/helm/traefik/examples/whoami.yaml` |
| cert-manager Helm chart/application | `v1.21.1` | `infrastructure/live/_common/cert-manager.hcl` |
| Argo CD Helm chart | `10.8.1` | `infrastructure/live/_common/argocd.hcl` |
| Argo CD application | `v3.5.2` | upstream chart `10.8.1` |
| Terraform CLI | `>= 1.8.0` | `infrastructure/modules/*/versions.tf` |
| AWS provider | `>= 5.0, < 7.0` | `infrastructure/modules/*/versions.tf` |
| Amazon Linux | AL2023 current patched x86_64 AMI | EC2 module via AWS SSM public parameter |

## Ownership

- Operators invoke **Terragrunt only** for infrastructure and platform lifecycle.
- EC2 lifecycle and AWS compute settings are owned by `infrastructure/modules/ec2`.
- K3s installation/upgrades are owned independently by `infrastructure/modules/k3s` through AWS Systems Manager.
- Traefik, cert-manager and Argo CD are Terraform `helm_release` resources driven through Terragrunt leaf units.
- Helm chart versions live in `infrastructure/live/_common/{traefik,cert-manager,argocd}.hcl`.
- `kubernetes/helm/*/values.yaml` contains only upstream chart values; local wrapper charts were intentionally removed.

## Verify state through Terragrunt

```bash
cd infrastructure/live/dev/us-east-1
terragrunt run --all output
```

Retrieve kubeconfig through the K3s unit if `kubectl` verification is needed:

```bash
cd k3s
terragrunt output -raw kubeconfig > ~/.kube/k3s-dev-us-east-1.yaml
```

Then, optionally:

```bash
export KUBECONFIG=~/.kube/k3s-dev-us-east-1.yaml
kubectl get nodes -o wide
kubectl -n traefik get pods,svc
kubectl -n cert-manager get pods
kubectl -n argocd get pods
```
