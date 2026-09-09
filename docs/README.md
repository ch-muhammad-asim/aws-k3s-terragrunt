# Repository architecture

The repository separates AWS networking, EC2 compute, K3s configuration, and Kubernetes add-ons into independent lifecycle boundaries.

## Architecture and research guides

- [`kubernetes-platform-comparison/README.md`](kubernetes-platform-comparison/README.md) - **central comparison hub** covering K3s, RKE2, Talos Linux, k0s, MicroK8s, kubeadm, k3d, Docker/Podman Compose, single-node, multi-node, HA, security/compliance, operational complexity, and repository-specific recommendations.
- [`k3s-vs-kubeadm/README.md`](k3s-vs-kubeadm/README.md) - detailed K3s vs kubeadm research guide, including single-node, multi-node, HA/non-HA decisions, native K3s, K3s inside Docker, k3d, security, networking, storage, and human-readable architecture explanations.
- [`k3s-vs-kubeadm/open-source-kubernetes-landscape.md`](k3s-vs-kubeadm/open-source-kubernetes-landscape.md) - explains which projects are open-source Kubernetes distributions versus an OS, bootstrap tool, or development tool; includes K3s, RKE2, k0s, MicroK8s, Talos Linux, kubeadm, k3d, licensing, and production-fit guidance.
- [`k3s-vs-kubeadm/architecture.svg`](k3s-vs-kubeadm/architecture.svg) - visual comparison of native K3s, K3s-in-Docker/k3d, and kubeadm.
- [`k3s/README.md`](k3s/README.md) - K3s topology and deployment guidance for this repository.
- [`k3s/architecture.md`](k3s/architecture.md) - GitHub-rendered diagrams for single-node, multi-node, HA and single-host lab topologies.
- [`diagrams/k3s-platform-overview.svg`](diagrams/k3s-platform-overview.svg) - AWS/K3s platform architecture used by this repository.

```text
infrastructure/
├── modules/
│   ├── vpc/
│   ├── ec2/
│   └── k3s/
└── live/
    ├── root.hcl
    ├── _common/
    │   ├── vpc.hcl
    │   ├── ec2.hcl
    │   └── k3s.hcl
    └── dev/
        ├── env.hcl
        └── us-east-1/
            ├── region.hcl
            ├── vpc/terragrunt.hcl
            ├── ec2/terragrunt.hcl
            └── k3s/terragrunt.hcl
```

## Dependency graph

```text
VPC -> EC2 -> K3s -> Traefik -> cert-manager -> Argo CD
```

Each Terraform/Terragrunt unit owns one lifecycle boundary:

- `vpc` owns networking.
- `ec2` owns the instance, EIP, IAM/SSM access, security group and EBS settings.
- `k3s` owns K3s installation/configuration on the existing instance through an AWS Systems Manager association.
- Helm directories own Kubernetes platform add-ons.

Updating the K3s version therefore updates the K3s SSM association rather than replacing the EC2 instance. Compute changes can also be reviewed independently from Kubernetes distribution changes.

## Design rules

1. **One concern per module/state.** EC2 resources do not belong in the K3s module and K3s bootstrap logic does not belong in the EC2 module.
2. **Reusable modules contain no environment values.** Environment-specific values stay under `infrastructure/live`.
3. **Shared component defaults live once.** Baseline EC2 sizing and K3s version pins live under `infrastructure/live/_common`.
4. **Leaf units only wire dependencies and overrides.** A new region does not copy full Terraform modules.
5. **Dependencies are explicit.** K3s consumes EC2 outputs; EC2 consumes VPC outputs.
6. **Operators use the root command interface.** `Makefile` and scripts centralize path resolution.
7. **Version upgrades must be explicit.** K3s and Helm application versions remain pinned and auditable in Git.

## Add another region

Create thin region units only:

```text
infrastructure/live/dev/eu-west-1/
├── region.hcl
├── vpc/terragrunt.hcl
├── ec2/terragrunt.hcl
└── k3s/terragrunt.hcl
```

Then use the same interface:

```bash
make plan ENV=dev REGION=eu-west-1
make apply ENV=dev REGION=eu-west-1
make kubeconfig ENV=dev REGION=eu-west-1
```

## Add another environment

Create the environment metadata and required region units, for example:

```text
infrastructure/live/prod/env.hcl
infrastructure/live/prod/us-east-1/...
```

CI receives environment and region as parameters:

```bash
make plan ENV="$ENVIRONMENT" REGION="$AWS_REGION"
```

## State migration note

The repository previously used a combined `k3s-ec2` Terraform module/state. If that older layout has already been applied to a real AWS account, do **not** blindly apply this split over the old state. Back up the state and migrate/import the existing EC2 resources into the new EC2 state before allowing the K3s state to manage only its SSM association.

For a new deployment, no migration is required.
