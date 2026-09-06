# AWS EC2 K3s with Terraform + Terragrunt

A clean, cost-conscious single-node K3s deployment on AWS EC2 with version-pinned Traefik, cert-manager, and Argo CD Helm deployments. This repository intentionally contains **no Hermes agent, Bedrock IAM, model configuration, or application manifests**.

## Architecture

- 1 AWS VPC
- 1 public subnet
- Internet Gateway + public route table
- 1 EC2 instance running K3s server **and workloads**
- 1 Elastic IP for a stable Kubernetes API / ingress endpoint
- Security group:
  - TCP 6443 only from your operator CIDR
  - TCP 80/443 from configurable ingress CIDRs
  - no inbound SSH
- AWS Systems Manager (SSM) for shell access
- K3s bundled Traefik **disabled**
- Helm-managed Traefik ingress controller
- K3s ServiceLB used for the Traefik `LoadBalancer` Service
- cert-manager for certificate lifecycle / Let's Encrypt
- Argo CD for GitOps
- K3s local-path storage enabled by default
- S3 Terraform state via Terragrunt

> This is intentionally a single-node cluster. It is suitable for an initial/small deployment where cost matters more than node-level HA. Move to multiple physical EC2 instances when you need real HA.

## Repository layout

```text
.
├── VERSIONS.md
├── kubernetes/
│   └── helm/
│       ├── README.md
│       ├── traefik/
│       │   ├── Chart.yaml
│       │   ├── values.yaml
│       │   ├── values-https-redirect.example.yaml
│       │   ├── install.sh
│       │   ├── test.sh
│       │   ├── uninstall.sh
│       │   ├── examples/whoami.yaml
│       │   └── README.md
│       ├── cert-manager/
│       │   ├── Chart.yaml
│       │   ├── values.yaml
│       │   ├── install.sh
│       │   ├── test.sh
│       │   ├── uninstall.sh
│       │   ├── examples/
│       │   │   ├── selfsigned-smoke-test.yaml
│       │   │   ├── cloudflare-secret.example.yaml
│       │   │   ├── clusterissuer-staging.example.yaml
│       │   │   ├── clusterissuer-production.example.yaml
│       │   │   ├── certificate.example.yaml
│       │   │   └── ingress-tls.example.yaml
│       │   └── README.md
│       └── argocd/
│           ├── Chart.yaml
│           ├── values.yaml
│           ├── values-traefik.example.yaml
│           ├── install.sh
│           ├── uninstall.sh
│           └── README.md
├── terraform/
│   └── modules/
│       ├── vpc/
│       └── k3s-ec2/
└── terragrunt/
    ├── root.hcl
    └── env/dev/region/us-east-1/
        ├── region.hcl
        ├── vpc/terragrunt.hcl
        └── k3s/terragrunt.hcl
```

## Prerequisites

- AWS CLI authenticated to the target AWS account
- Terraform >= 1.8
- Terragrunt 1.x
- Helm 3
- kubectl
- `curl`
- permissions to create VPC, EC2, IAM, S3 state, and SSM-related resources

## Pinned platform versions

- K3s: `v1.36.4+k3s1`
- Traefik Helm chart: `41.4.0`
- Traefik Proxy: `v3.7.12`
- cert-manager: `v1.21.1`
- Argo CD Helm chart: `10.8.1`
- Argo CD application: `v3.5.2`

See [`VERSIONS.md`](VERSIONS.md) for the complete version matrix.

## Deploy infrastructure

### 1. Check AWS identity

```bash
aws sts get-caller-identity
```

### 2. Deploy VPC

```bash
cd terragrunt/env/dev/region/us-east-1/vpc
terragrunt backend bootstrap
terragrunt init
terragrunt plan
terragrunt apply
```

### 3. Deploy K3s

```bash
cd ../k3s
terragrunt init
terragrunt plan
terragrunt apply
```

The Kubernetes API CIDR is discovered from `https://checkip.amazonaws.com` unless `TG_OPERATOR_CIDR` is set:

```bash
export TG_OPERATOR_CIDR="203.0.113.0/24"
terragrunt plan
terragrunt apply
```

### Existing cluster warning

The K3s unit now sets `enable_traefik = false` because Traefik is installed separately with Helm. If an EC2 node already exists from the earlier configuration, **review the plan before applying**. The module uses `user_data_replace_on_change = true`, so changing bootstrap flags can replace the node.

## Get kubeconfig without SSH

```bash
cd terragrunt/env/dev/region/us-east-1/k3s

INSTANCE_ID=$(terragrunt output -raw instance_id)
PUBLIC_IP=$(terragrunt output -raw public_ip)

CMD_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["sudo cat /etc/rancher/k3s/k3s.yaml"]' \
  --query 'Command.CommandId' \
  --output text)

sleep 2
mkdir -p ~/.kube
aws ssm get-command-invocation \
  --command-id "$CMD_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardOutputContent' \
  --output text \
  | sed "s/127.0.0.1/$PUBLIC_IP/" \
  > ~/.kube/k3s-dev.yaml

chmod 600 ~/.kube/k3s-dev.yaml
export KUBECONFIG=~/.kube/k3s-dev.yaml
kubectl get nodes -o wide
```

## Deploy the Kubernetes platform

Install in this order:

### 1. Traefik

```bash
cd kubernetes/helm/traefik
./install.sh
./test.sh
```

### 2. cert-manager

```bash
cd ../cert-manager
./install.sh
./test.sh
```

### 3. Argo CD

```bash
cd ../argocd
./install.sh
```

Full documentation:

- `kubernetes/helm/traefik/README.md`
- `kubernetes/helm/cert-manager/README.md`
- `kubernetes/helm/argocd/README.md`

## Verify everything

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

## Quick application test through Traefik

```bash
kubectl apply -f kubernetes/helm/traefik/examples/whoami.yaml
kubectl -n traefik-test rollout status deployment/whoami

PUBLIC_IP=$(cd terragrunt/env/dev/region/us-east-1/k3s && terragrunt output -raw public_ip)
curl -H 'Host: whoami.local' "http://${PUBLIC_IP}/"
```

## Connect to the node with SSM

```bash
cd terragrunt/env/dev/region/us-east-1/k3s
aws ssm start-session --target "$(terragrunt output -raw instance_id)"
```

No SSH security-group rule or EC2 key pair is required.

## Change EC2 size

Edit `terragrunt/env/dev/region/us-east-1/k3s/terragrunt.hcl`:

```hcl
instance_type = "t3.medium"
```

For a very small workload, `t3.small` may be enough. Traefik + cert-manager + Argo CD add control-plane workload, so `t3.medium` is the safer default.

## Security notes

- Kubernetes API `6443` is restricted to `TG_OPERATOR_CIDR`.
- SSH `22` is not opened; use SSM Session Manager.
- IMDSv2 is required.
- The root EBS volume is encrypted.
- Traefik dashboard is not publicly exposed by default.
- cert-manager Cloudflare examples contain placeholders only; never commit a real API token.
- Do not commit kubeconfig or Terraform state.
- For production, consider private subnets, a dedicated load balancer, external secrets, backup/restore, monitoring, and multiple EC2 nodes.

## Destroy

Remove Kubernetes platform components first:

```bash
cd kubernetes/helm/argocd && ./uninstall.sh
cd ../cert-manager && ./uninstall.sh
cd ../traefik && ./uninstall.sh
```

Then destroy infrastructure:

```bash
cd ../../../terragrunt/env/dev/region/us-east-1/k3s
terragrunt destroy

cd ../vpc
terragrunt destroy
```
