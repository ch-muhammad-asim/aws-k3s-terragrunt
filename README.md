# AWS EC2 K3s Platform with Terraform, Terragrunt and Helm

A version-pinned, cost-conscious K3s platform on AWS EC2. Terraform modules, live Terragrunt configuration, and Kubernetes platform add-ons are separated so environments and regions can be added without copying a monolithic stack or embedding brittle relative paths.

The repository contains no Hermes, Bedrock, model, or agent-specific configuration.

## Architecture

- AWS VPC and public subnet
- single EC2 K3s server/worker for the current cost-optimized profile
- Elastic IP for the Kubernetes API and ingress endpoint
- SSM Session Manager instead of SSH
- encrypted gp3 root volume and IMDSv2
- K3s bundled Traefik disabled
- Helm-managed Traefik ingress controller
- cert-manager for certificate lifecycle and ACME
- Argo CD for GitOps
- Terragrunt S3 remote state with native lockfile support

The current topology is intentionally single-node and is not node-level HA. The repository layout is designed to scale independently from that initial topology.

## Repository layout

```text
.
├── Makefile
├── README.md
├── VERSIONS.md
├── docs/
│   └── repository-layout.md
├── infrastructure/
│   ├── modules/
│   │   ├── vpc/
│   │   └── k3s-ec2/
│   └── live/
│       ├── root.hcl
│       ├── _common/
│       │   ├── vpc.hcl
│       │   └── k3s.hcl
│       └── dev/
│           ├── env.hcl
│           └── us-east-1/
│               ├── region.hcl
│               ├── vpc/terragrunt.hcl
│               └── k3s/terragrunt.hcl
├── kubernetes/
│   └── helm/
│       ├── traefik/
│       ├── cert-manager/
│       └── argocd/
└── scripts/
    ├── kubeconfig.sh
    └── platform.sh
```

### Why this layout scales

- `infrastructure/modules` contains reusable Terraform only.
- `infrastructure/live/_common` owns shared component defaults and version pins.
- `infrastructure/live/<environment>/<region>/<component>` contains thin live units only.
- the K3s-to-VPC dependency is anchored to `region.hcl`; there is no `../vpc` or multi-level `../../..` traversal.
- cluster resource names include environment and region to avoid cross-region IAM-name collisions.
- operators and CI run the same root-level `make` interface rather than hard-coding deep paths.
- remote-state identity is derived from environment, region and component rather than repository depth, so this directory refactor preserves the original backend keys.

See [`docs/repository-layout.md`](docs/repository-layout.md) for the scaling model.

## Prerequisites

- AWS CLI
- Terraform `>= 1.8.0`
- Terragrunt `1.x`
- Helm 3
- kubectl
- curl
- git
- AWS permissions for VPC, EC2, IAM, S3 and Systems Manager

Verify tooling from the repository root:

```bash
make check
aws sts get-caller-identity
```

## Pinned versions

- K3s `v1.36.4+k3s1`
- Traefik Helm chart `41.4.0`
- Traefik Proxy `v3.7.12`
- cert-manager `v1.21.1`
- Argo CD Helm chart `10.8.1`
- Argo CD `v3.5.2`

See [`VERSIONS.md`](VERSIONS.md) for the complete matrix.

## Environment and region selection

The command interface is parameterized:

```bash
make plan ENV=dev REGION=us-east-1
```

`dev` and `us-east-1` are defaults, so for the current stack this is equivalent to:

```bash
make plan
```

No documentation or automation needs to know the physical depth of a Terragrunt unit.

## Deploy infrastructure

From the repository root:

```bash
make bootstrap ENV=dev REGION=us-east-1
make init      ENV=dev REGION=us-east-1
make plan      ENV=dev REGION=us-east-1
make apply     ENV=dev REGION=us-east-1
```

The Kubernetes API defaults to the caller's current public `/32`. To use an office or VPN range:

```bash
export TG_OPERATOR_CIDR="203.0.113.0/24"
make plan ENV=dev REGION=us-east-1
make apply ENV=dev REGION=us-east-1
```

### Existing deployments

This refactor keeps the original S3 state-object naming convention so moving the live configuration does not intentionally orphan existing state. However, resource naming is now region-aware (`k3s-dev-us-east-1` rather than `k3s-dev`). If infrastructure already exists, review `make plan` before applying because name changes can replace resources, and the K3s module also uses `user_data_replace_on_change = true`.

## Retrieve kubeconfig

Use the root-level helper; it discovers the selected stack and waits for the SSM command rather than using a fixed sleep:

```bash
make kubeconfig ENV=dev REGION=us-east-1
```

Default output:

```text
~/.kube/k3s-dev-us-east-1.yaml
```

Then:

```bash
export KUBECONFIG=~/.kube/k3s-dev-us-east-1.yaml
kubectl get nodes -o wide
kubectl version
```

## Deploy the Kubernetes platform

The supported order is Traefik -> cert-manager -> Argo CD.

```bash
make platform-install
make platform-test
```

The scripts call the component-local install/test scripts and fail on the first unsuccessful step.

Detailed component documentation:

- `kubernetes/helm/traefik/README.md`
- `kubernetes/helm/cert-manager/README.md`
- `kubernetes/helm/argocd/README.md`

## Verify the platform

```bash
kubectl get nodes -o wide
kubectl get ingressclass

helm -n traefik list
helm -n cert-manager list
helm -n argocd list

kubectl -n traefik get pods,svc
kubectl -n cert-manager get pods
kubectl -n argocd get pods
```

## Infrastructure outputs and node access

```bash
make outputs ENV=dev REGION=us-east-1
make ssm     ENV=dev REGION=us-east-1
```

There is no SSH ingress rule or EC2 key-pair dependency.

## Component-specific planning

```bash
make vpc-plan ENV=dev REGION=us-east-1
make k3s-plan ENV=dev REGION=us-east-1
```

The same interface works for another environment/region after its thin live units are added.

## Destroy

Remove Kubernetes add-ons in reverse order, then infrastructure:

```bash
make platform-uninstall
make destroy ENV=dev REGION=us-east-1
```

cert-manager CRDs are intentionally retained by its chart configuration; review cert-manager custom resources before deleting those CRDs manually.

## Security notes

- Kubernetes API `6443` is restricted to `TG_OPERATOR_CIDR`.
- SSH `22` is not exposed; use SSM.
- IMDSv2 is required.
- EBS is encrypted.
- Traefik dashboard is not publicly exposed by default.
- Cloudflare examples contain placeholders only; never commit a real token.
- Never commit kubeconfig, Terraform state, cloud credentials, or private keys.
- For production, add multi-node failure domains, private subnets, backup/restore, observability, secret management and a production load-balancing strategy.
