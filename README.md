# AWS EC2 K3s Platform with Terragrunt

A version-pinned K3s platform on AWS where **Terragrunt is the only deployment/orchestration interface**. Terraform remains the execution engine underneath Terragrunt, and the HashiCorp Helm provider manages Kubernetes add-ons declaratively.

There is no Makefile, no platform install/uninstall shell wrapper, and no requirement to run Helm CLI commands to build the platform.

## Architecture

![K3s on AWS platform architecture](docs/diagrams/k3s-platform-overview.svg)

```text
Terragrunt DAG

VPC
 |
 v
EC2
 |
 v
K3s
 |
 v
Traefik
 |
 v
cert-manager
 |
 v
Argo CD
```

Every box is an independent Terragrunt unit with its own Terraform state. Terragrunt dependency blocks define the order.

- `vpc` owns AWS networking.
- `ec2` owns EC2, EIP, IAM/SSM, security groups and EBS.
- `k3s` installs/upgrades K3s through AWS Systems Manager without replacing EC2.
- `traefik`, `cert-manager` and `argocd` use a reusable Terraform `helm_release` module, but are planned/applied/destroyed through Terragrunt.
- K3s publishes the Kubernetes API/client material to scoped SSM Parameter Store keys. Downstream Terragrunt units consume the resulting K3s outputs, so no kubeconfig bootstrap script is required for deployment.

The current compute profile is a single EC2 K3s server/worker. It is intentionally non-HA; the module/state boundaries allow later evolution toward multi-node HA.

## Repository layout

```text
.
├── README.md
├── VERSIONS.md
├── docs/
│   ├── README.md
│   ├── terragrunt-workflow/README.md
│   ├── diagrams/
│   ├── k3s/
│   ├── k3s-vs-kubeadm/
│   └── kubernetes-platform-comparison/
├── infrastructure/
│   ├── modules/
│   │   ├── vpc/
│   │   ├── ec2/
│   │   ├── k3s/
│   │   └── helm-release/
│   └── live/
│       ├── root.hcl
│       ├── _common/
│       │   ├── vpc.hcl
│       │   ├── ec2.hcl
│       │   ├── k3s.hcl
│       │   ├── traefik.hcl
│       │   ├── cert-manager.hcl
│       │   └── argocd.hcl
│       └── dev/us-east-1/
│           ├── vpc/terragrunt.hcl
│           ├── ec2/terragrunt.hcl
│           ├── k3s/terragrunt.hcl
│           ├── traefik/terragrunt.hcl
│           ├── cert-manager/terragrunt.hcl
│           └── argocd/terragrunt.hcl
└── kubernetes/helm/
    ├── traefik/values.yaml
    ├── cert-manager/values.yaml
    └── argocd/values.yaml
```

## Prerequisites

Required for deployment:

- Terragrunt `1.x`
- Terraform `>= 1.8.0` as the Terragrunt execution engine
- AWS credentials with the permissions required by the stack
- network access to Terraform/Helm provider registries and upstream Helm chart repositories

`kubectl` is optional for post-deployment validation. The Helm CLI is not required for normal deployment.

## Pinned versions

- K3s `v1.36.4+k3s1`
- HashiCorp Helm provider `3.2.0`
- Traefik Helm chart `41.4.0`
- Traefik Proxy `v3.7.12`
- cert-manager chart/application `v1.21.1`
- Argo CD Helm chart `10.8.1`
- Argo CD application `v3.5.2`

See [`VERSIONS.md`](VERSIONS.md).

## Deploy with Terragrunt only

Choose the environment/region directory:

```bash
cd infrastructure/live/dev/us-east-1
```

Bootstrap the remote S3 backend from one unit:

```bash
cd vpc
terragrunt backend bootstrap
cd ..
```

Initialize all units:

```bash
terragrunt run --all init
```

Review the stack:

```bash
terragrunt run --all plan
```

Apply the complete dependency graph:

```bash
terragrunt run --all apply
```

Terragrunt applies dependencies in order:

```text
VPC -> EC2 -> K3s -> Traefik -> cert-manager -> Argo CD
```

On a brand-new environment, downstream Kubernetes units use mock dependency outputs for `init`/`plan` because the K3s API does not exist yet. After the first successful apply, repeat `terragrunt run --all plan` to get a fully live refresh of every Helm release.

## Work on one component

Each lifecycle can still be reviewed independently:

```bash
cd infrastructure/live/dev/us-east-1/ec2
terragrunt plan
terragrunt apply
```

Examples:

```bash
cd ../k3s && terragrunt plan
cd ../traefik && terragrunt plan
cd ../cert-manager && terragrunt plan
cd ../argocd && terragrunt plan
```

Do not call Terraform directly; Terragrunt supplies the parent configuration, remote state, provider generation, shared inputs and dependencies.

## Kubernetes API access

The API defaults to the current operator public `/32`. Override it before planning/applying when office/VPN access is required:

```bash
export TG_OPERATOR_CIDR="203.0.113.0/24"
```

## Retrieve kubeconfig through Terragrunt

K3s publishes the API endpoint and base64 client material after the SSM installation association succeeds. The K3s Terraform unit assembles a kubeconfig output.

```bash
cd infrastructure/live/dev/us-east-1/k3s
mkdir -p ~/.kube
terragrunt output -raw kubeconfig > ~/.kube/k3s-dev-us-east-1.yaml
chmod 600 ~/.kube/k3s-dev-us-east-1.yaml
```

Optional verification:

```bash
export KUBECONFIG=~/.kube/k3s-dev-us-east-1.yaml
kubectl get nodes -o wide
kubectl get pods -A
```

The kubeconfig output is sensitive. Remote Terraform state must be treated as sensitive data and access to the S3 state bucket must be tightly controlled.

## Platform add-ons

No `helm install` or shell installer is used. Terragrunt drives the reusable `infrastructure/modules/helm-release` module, which uses HashiCorp Helm provider `3.2.0`.

The source values remain reviewable under `kubernetes/helm/*/values.yaml`, while chart identity/version live in `infrastructure/live/_common/*.hcl`.

Apply an individual release with Terragrunt:

```bash
cd infrastructure/live/dev/us-east-1/traefik
terragrunt plan
terragrunt apply
```

The same pattern applies to `cert-manager` and `argocd`.

## Outputs

From any unit:

```bash
terragrunt output
```

Across the region stack:

```bash
cd infrastructure/live/dev/us-east-1
terragrunt run --all output
```

## Destroy

Destroy the whole graph through Terragrunt:

```bash
cd infrastructure/live/dev/us-east-1
terragrunt run --all destroy
```

Terragrunt uses the dependency graph to destroy dependents before dependencies.

## Existing-state migration

Two historical layouts may require migration before applying this revision:

1. An older revision used a combined `k3s-ec2` Terraform state. Existing EC2 resources must be migrated/imported into the split EC2 state before applying the current stack.
2. An older revision installed Traefik, cert-manager and Argo CD outside Terraform state. If those Helm releases exist, import them into their Terragrunt unit states before applying:

```bash
cd infrastructure/live/dev/us-east-1/traefik
terragrunt import helm_release.this traefik/traefik

cd ../cert-manager
terragrunt import helm_release.this cert-manager/cert-manager

cd ../argocd
terragrunt import helm_release.this argocd/argocd
```

Always review `terragrunt plan` after import because this revision manages the official upstream charts directly instead of local wrapper charts.

## Security notes

- Kubernetes API `6443` is restricted to `TG_OPERATOR_CIDR`.
- SSH `22` is not exposed; the node uses AWS Systems Manager.
- IMDSv2 is required.
- EBS is encrypted.
- K3s kubeconfig credentials are stored in scoped SSM SecureString parameters and sensitive Terraform state.
- Traefik dashboard is not public by default.
- Never commit kubeconfig, Terraform state, cloud credentials, Cloudflare tokens or private keys.

For the detailed command model and state/dependency explanation, see [`docs/terragrunt-workflow/README.md`](docs/terragrunt-workflow/README.md).
