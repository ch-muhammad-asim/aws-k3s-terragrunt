# Repository architecture

The repository separates AWS networking, EC2 compute, K3s configuration and Kubernetes add-ons into independent **Terragrunt units**. Terragrunt is the single operator interface for plan/apply/destroy.

## Architecture and research guides

- [`terragrunt-workflow/README.md`](terragrunt-workflow/README.md) - canonical deployment workflow: backend bootstrap, run-all DAG, component operations, kubeconfig output, state/security and migration.
- [`kubernetes-platform-comparison/README.md`](kubernetes-platform-comparison/README.md) - central comparison of K3s, RKE2, Talos Linux, k0s, MicroK8s, kubeadm, k3d and Compose.
- [`k3s-vs-kubeadm/README.md`](k3s-vs-kubeadm/README.md) - K3s vs kubeadm research, HA/non-HA, K3s-in-Docker and distribution choices.
- [`k3s-vs-kubeadm/open-source-kubernetes-landscape.md`](k3s-vs-kubeadm/open-source-kubernetes-landscape.md) - open-source project roles and licensing.
- [`k3s-vs-kubeadm/architecture.svg`](k3s-vs-kubeadm/architecture.svg) - visual K3s/kubeadm comparison.
- [`k3s/README.md`](k3s/README.md) and [`k3s/architecture.md`](k3s/architecture.md) - K3s topology guidance.
- [`diagrams/k3s-platform-overview.svg`](diagrams/k3s-platform-overview.svg) - AWS/K3s platform architecture.

## Terragrunt dependency graph

```text
VPC -> EC2 -> K3s -> Traefik -> cert-manager -> Argo CD
```

Each component has its own state boundary:

```text
infrastructure/
├── modules/
│   ├── vpc/
│   ├── ec2/
│   ├── k3s/
│   └── helm-release/
└── live/
    ├── root.hcl
    ├── _common/
    │   ├── vpc.hcl
    │   ├── ec2.hcl
    │   ├── k3s.hcl
    │   ├── traefik.hcl
    │   ├── cert-manager.hcl
    │   └── argocd.hcl
    └── dev/
        ├── env.hcl
        └── us-east-1/
            ├── region.hcl
            ├── vpc/terragrunt.hcl
            ├── ec2/terragrunt.hcl
            ├── k3s/terragrunt.hcl
            ├── traefik/terragrunt.hcl
            ├── cert-manager/terragrunt.hcl
            └── argocd/terragrunt.hcl
```

## Lifecycle boundaries

- `vpc` owns networking.
- `ec2` owns EC2, EIP, IAM/SSM access, security groups and EBS.
- `k3s` owns K3s installation/configuration and publishes client material after K3s is healthy.
- `traefik`, `cert-manager` and `argocd` consume K3s outputs and manage official upstream charts through Terraform `helm_release` resources.

Updating the K3s version therefore updates the K3s SSM association rather than replacing EC2. Updating a chart version only changes the corresponding Helm unit.

## Design rules

1. **Terragrunt is the operator interface.** No Makefile or deployment shell wrapper is required.
2. **One concern per module/state.** EC2, K3s and each platform add-on have independent lifecycle/state boundaries.
3. **Reusable modules contain no environment values.** Environment-specific values stay under `infrastructure/live`.
4. **Shared component defaults live once.** Baseline sizing, K3s version and Helm chart pins live under `infrastructure/live/_common`.
5. **Leaf units only wire dependencies and overrides.** A new region does not copy Terraform module logic.
6. **Dependencies are explicit.** K3s consumes EC2 outputs; platform add-ons consume K3s connection outputs.
7. **Version upgrades are explicit.** Runtime/provider/chart versions are pinned and auditable in Git.
8. **Secrets stay out of Git.** K3s client material is sensitive, stored in SSM SecureString parameters and protected remote state.

## Add another region

Create thin units:

```text
infrastructure/live/dev/eu-west-1/
├── region.hcl
├── vpc/terragrunt.hcl
├── ec2/terragrunt.hcl
├── k3s/terragrunt.hcl
├── traefik/terragrunt.hcl
├── cert-manager/terragrunt.hcl
└── argocd/terragrunt.hcl
```

Then operate from that region directory:

```bash
terragrunt run --all plan
terragrunt run --all apply
```

## State migration note

An older repository revision used a combined `k3s-ec2` state, and an intermediate revision installed platform Helm releases outside Terraform state. Existing environments must migrate/import those resources before applying this layout. New deployments require no migration.
