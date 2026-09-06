# AWS EC2 K3s with Terraform + Terragrunt

A clean, cost-conscious single-node K3s deployment on AWS EC2. This repository intentionally contains **no Hermes agent, Bedrock IAM, model configuration, or application manifests**.

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
- K3s default Traefik ingress controller enabled by default
- K3s local-path storage enabled by default
- S3 Terraform state via Terragrunt

> This is intentionally a single-node cluster. It is suitable for an initial/small deployment where cost matters more than node-level HA. Move to multiple physical EC2 instances when you need real HA.

## Repository layout

```text
.
├── VERSIONS.md
├── kubernetes/
│   └── helm/
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
- permissions to create VPC, EC2, IAM, S3 state, and SSM-related resources
- `curl` installed locally (used by Terragrunt to discover your public /32 for the Kubernetes API)

## Pinned platform versions

- K3s: `v1.36.4+k3s1`
- Argo CD Helm chart: `10.8.1`
- Argo CD application: `v3.5.2`

See [`VERSIONS.md`](VERSIONS.md) for the complete version matrix. The K3s version is pinned directly in the Terragrunt K3s unit; the install no longer follows a moving `stable` channel.

## Deploy

### 1. Check your AWS identity

```bash
aws sts get-caller-identity
```

### 2. Deploy the VPC

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

By default, the Kubernetes API CIDR is discovered from `https://checkip.amazonaws.com` at Terragrunt evaluation time.

To use a fixed office/VPN CIDR instead:

```bash
export TG_OPERATOR_CIDR="203.0.113.0/24"
terragrunt plan
terragrunt apply
```

## Get kubeconfig without SSH

After the instance finishes bootstrapping:

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

If SSM has not registered the instance yet, wait a minute and retry.

## Connect to the node with SSM

```bash
aws ssm start-session --target "$(terragrunt output -raw instance_id)"
```

No SSH security-group rule or EC2 key pair is required.

## Deploy a quick test application

```bash
export KUBECONFIG=~/.kube/k3s-dev.yaml

kubectl create deployment nginx --image=nginx:alpine
kubectl expose deployment nginx --port=80

cat <<'YAML' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
YAML

PUBLIC_IP=$(terragrunt output -raw public_ip)
curl "http://$PUBLIC_IP"
```

## Install Argo CD

After K3s is reachable with `kubectl`, deploy the pinned Argo CD Helm chart:

```bash
cd kubernetes/helm/argocd
./install.sh
```

The wrapper chart pins Argo CD Helm chart `10.8.1` and Argo CD `v3.5.2`. For the full validation, manual install, Traefik ingress, password retrieval, upgrade, and uninstall commands, see `kubernetes/helm/argocd/README.md`.

## Change EC2 size

Edit:

```text
terragrunt/env/dev/region/us-east-1/k3s/terragrunt.hcl
```

For example:

```hcl
instance_type = "t3.medium"
```

For a very small workload, `t3.small` may be enough. For more application pods, use `t3.medium` or larger.

## Security notes

- Kubernetes API `6443` is not open to the internet by default; it is restricted to `TG_OPERATOR_CIDR`.
- SSH `22` is not opened; use SSM Session Manager.
- IMDSv2 is required.
- The root EBS volume is encrypted.
- Do not commit kubeconfig or Terraform state.
- For production, consider private subnets, a load balancer, external secrets, backup/restore, monitoring, and multiple EC2 nodes.

## Destroy

Destroy K3s first, then the VPC:

```bash
cd terragrunt/env/dev/region/us-east-1/k3s
terragrunt destroy

cd ../vpc
terragrunt destroy
```
