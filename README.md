# AWS EC2 K3s Platform with Terraform, Terragrunt and Helm

A version-pinned K3s platform on AWS with clear lifecycle boundaries between networking, compute, K3s configuration, and Kubernetes add-ons.

## Architecture

![K3s on AWS platform architecture](docs/diagrams/k3s-platform-overview.svg)

```text
VPC -> EC2 -> K3s -> Traefik -> cert-manager -> Argo CD
```

- VPC is managed independently.
- EC2 compute, IAM/SSM, security group, EIP and EBS are managed by the EC2 module.
- K3s installation and upgrades are managed by a separate K3s module through AWS Systems Manager.
- K3s bundled Traefik is disabled.
- Traefik, cert-manager and Argo CD are version-pinned Helm deployments.
- Terraform state is separated by live component.

The current compute profile is a single EC2 K3s server/worker to keep the initial deployment cost-conscious. It is not node-level HA; the module/state separation is designed so the topology can evolve without coupling K3s lifecycle to one EC2 resource definition.

For K3s topology guidance and the K3s vs kubeadm research/decision matrix, see [`docs/k3s/`](docs/k3s/).

## Repository layout

```text
.
├── Makefile
├── README.md
├── VERSIONS.md
├── docs/
│   ├── README.md
│   ├── diagrams/
│   │   └── k3s-platform-overview.svg
│   └── k3s/
│       ├── README.md
│       ├── architecture.md
│       └── kubeadm-comparison.md
├── infrastructure/
│   ├── modules/
│   │   ├── vpc/
│   │   ├── ec2/
│   │   └── k3s/
│   └── live/
│       ├── root.hcl
│       ├── _common/
│       │   ├── vpc.hcl
│       │   ├── ec2.hcl
│       │   └── k3s.hcl
│       └── dev/us-east-1/
│           ├── vpc/terragrunt.hcl
│           ├── ec2/terragrunt.hcl
│           └── k3s/terragrunt.hcl
├── kubernetes/helm/
│   ├── traefik/
│   ├── cert-manager/
│   └── argocd/
└── scripts/
    ├── kubeconfig.sh
    └── platform.sh
```

See [`docs/README.md`](docs/README.md) for the repository architecture and scaling rules.

## Module boundaries

### VPC

Owns networking only.

### EC2

Owns AWS compute infrastructure:

- Amazon Linux 2023 AMI resolution
- EC2 instance
- encrypted gp3 root volume
- IMDSv2
- Elastic IP
- security group/rules
- IAM role and instance profile
- SSM managed-instance permissions

It contains **no K3s installation logic**.

### K3s

Consumes the EC2 `instance_id` and `public_ip` outputs and manages K3s through an `AWS-RunShellScript` SSM association. Changing the K3s version updates K3s independently instead of changing EC2 user data and forcing an instance replacement.

The AWS provider supports waiting for an SSM association to reach `Success`; this module uses that behavior so a failed K3s bootstrap fails the infrastructure apply rather than silently continuing.

## Prerequisites

- AWS CLI
- Terraform `>= 1.8.0`
- Terragrunt `1.x`
- Helm 3
- kubectl
- curl
- git
- AWS permissions for VPC, EC2, IAM, S3 and Systems Manager

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

See [`VERSIONS.md`](VERSIONS.md).

## Deploy

All operator commands are run from the repository root. `ENV` and `REGION` are parameters instead of hard-coded traversal paths.

```bash
make bootstrap ENV=dev REGION=us-east-1
make init      ENV=dev REGION=us-east-1
make plan      ENV=dev REGION=us-east-1
make apply     ENV=dev REGION=us-east-1
```

The apply order is:

```text
VPC -> EC2 -> K3s
```

You can review/apply each lifecycle separately:

```bash
make vpc-plan ENV=dev REGION=us-east-1
make ec2-plan ENV=dev REGION=us-east-1
make k3s-plan ENV=dev REGION=us-east-1

make vpc-apply ENV=dev REGION=us-east-1
make ec2-apply ENV=dev REGION=us-east-1
make k3s-apply ENV=dev REGION=us-east-1
```

The Kubernetes API defaults to the current operator public `/32`. Override it for office/VPN access:

```bash
export TG_OPERATOR_CIDR="203.0.113.0/24"
make plan ENV=dev REGION=us-east-1
```

## Retrieve kubeconfig

```bash
make kubeconfig ENV=dev REGION=us-east-1
export KUBECONFIG=~/.kube/k3s-dev-us-east-1.yaml
kubectl get nodes -o wide
```

The helper reads EC2 identity/network outputs from the EC2 state and requires the K3s state to exist before retrieving `/etc/rancher/k3s/k3s.yaml` over SSM.

## Deploy Kubernetes platform add-ons

```bash
make platform-install
make platform-test
```

Installation order:

```text
Traefik -> cert-manager -> Argo CD
```

Verify:

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

## Outputs and node access

```bash
make outputs ENV=dev REGION=us-east-1
make ssm     ENV=dev REGION=us-east-1
```

There is no inbound SSH rule or EC2 key-pair dependency.

## Existing state warning

An earlier revision used one combined `k3s-ec2` module/state. If that revision has already provisioned a real environment, migrate the existing resources into the new EC2 state before applying this split. Do not run the new K3s state against an old combined state without reviewing/migrating it first. See `docs/README.md`.

New deployments require no state migration.

## Destroy

```bash
make platform-uninstall
make destroy ENV=dev REGION=us-east-1
```

Destroy order is K3s -> EC2 -> VPC.

## Security notes

- Kubernetes API `6443` is restricted to `TG_OPERATOR_CIDR`.
- SSH `22` is not exposed; use SSM.
- IMDSv2 is required.
- EBS is encrypted.
- Traefik dashboard is not public by default.
- Never commit kubeconfig, Terraform state, cloud credentials, Cloudflare tokens or private keys.
