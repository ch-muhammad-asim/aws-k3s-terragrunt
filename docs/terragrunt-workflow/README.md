# Terragrunt-only operating workflow

This repository intentionally exposes **Terragrunt as the only infrastructure/platform lifecycle CLI**.

Terraform is still the underlying engine and HashiCorp Helm provider manages Kubernetes charts, but operators do not run Terraform or Helm directly and there is no Makefile abstraction.

## Why this model

A Makefile around Terragrunt duplicates orchestration that Terragrunt already provides. The dependency graph belongs in HCL where CI and humans use the same source of truth.

```text
Terragrunt dependency graph

vpc
 |
ec2
 |
k3s
 |
traefik
 |
cert-manager
 |
argocd
```

This gives one consistent lifecycle:

```text
terragrunt init
terragrunt plan
terragrunt apply
terragrunt output
terragrunt destroy
```

and one multi-unit lifecycle:

```text
terragrunt run --all <command>
```

## First deployment

Start in the region stack:

```bash
cd infrastructure/live/dev/us-east-1
```

### Brand-new backend

Terragrunt 1.x requires backend provisioning to be explicitly enabled. If the S3 bucket in `root.hcl` does not exist yet, a plain `terragrunt run --all init` fails with `NoSuchBucket`.

For the very first initialization, run:

```bash
terragrunt run --all --backend-bootstrap init
```

`--backend-bootstrap` authorizes Terragrunt to create the remote-state resources defined by the `remote_state` block before Terraform initialization. This keeps backend creation inside Terragrunt; do not create the bucket manually with AWS CLI and do not add a separate Terraform bootstrap project.

Once the backend exists, use the normal lifecycle:

```bash
terragrunt run --all plan
terragrunt run --all apply
```

An equivalent explicit Terragrunt-only bootstrap sequence is:

```bash
cd vpc
terragrunt backend bootstrap
cd ..
terragrunt run --all init
```

Use one approach or the other; the single `run --all --backend-bootstrap init` command is the recommended first-run path.

Terragrunt orders the apply using dependency blocks; there is no hand-written install sequence in a Makefile or shell script.

### Why the explicit flag is necessary

Modern Terragrunt no longer creates remote backend infrastructure implicitly. This is intentional: creating an S3 bucket or other backend resources is a cloud-side mutation, so Terragrunt now requires explicit opt-in using `--backend-bootstrap` or the `TG_BACKEND_BOOTSTRAP=true` environment variable.

For CI, either keep the first-run flag explicit or set the environment variable only in the bootstrap workflow. Do not enable backend bootstrap globally unless you intentionally want Terragrunt to be allowed to create/update backend infrastructure on normal runs.

### Fresh-stack planning note

Before K3s exists, the Helm units cannot have a real Kubernetes connection. Their dependency blocks therefore provide mocks for `init`, `validate` and `plan`. The first complete apply creates K3s before Helm units are applied. Repeat `terragrunt run --all plan` after the first deployment for a plan based entirely on live Kubernetes state.

## Component lifecycle

Plan or apply one unit directly:

```bash
cd infrastructure/live/dev/us-east-1/traefik
terragrunt plan
terragrunt apply
```

The same pattern works for `vpc`, `ec2`, `k3s`, `cert-manager` and `argocd`.

## Kubeconfig

K3s publishes four scoped Parameter Store values after bootstrap:

```text
/k3s/<cluster>/kubeconfig/server
/k3s/<cluster>/kubeconfig/cluster-ca-data
/k3s/<cluster>/kubeconfig/client-certificate-data
/k3s/<cluster>/kubeconfig/client-key-data
```

The K3s Terraform module reads them only after the SSM association reports success and exposes a sensitive kubeconfig output.

```bash
cd infrastructure/live/dev/us-east-1/k3s
terragrunt output -raw kubeconfig > ~/.kube/k3s-dev-us-east-1.yaml
chmod 600 ~/.kube/k3s-dev-us-east-1.yaml
```

This replaces the old kubeconfig retrieval shell script.

## Helm releases through Terragrunt

Each platform leaf sources `infrastructure/modules/helm-release`.

The module:

- pins HashiCorp Helm provider `3.2.0`;
- uses K3s API/client outputs for provider authentication;
- installs the official upstream chart directly;
- waits for readiness/jobs;
- uses atomic install/upgrade behavior and cleanup on failure;
- keeps each release in its own Terraform state.

Values are stored under:

```text
kubernetes/helm/traefik/values.yaml
kubernetes/helm/cert-manager/values.yaml
kubernetes/helm/argocd/values.yaml
```

Chart repository/name/version are stored under:

```text
infrastructure/live/_common/traefik.hcl
infrastructure/live/_common/cert-manager.hcl
infrastructure/live/_common/argocd.hcl
```

No local wrapper `Chart.yaml`, `install.sh`, `uninstall.sh`, or `helm dependency update` step is needed.

## Destroy

From the region directory:

```bash
terragrunt run --all destroy
```

The reverse dependency graph removes Argo CD and cert-manager/Traefik before K3s, then removes EC2 and VPC.

## State and secrets

Remote state is S3-backed and encrypted. State still contains sensitive Kubernetes client material because Terraform providers need it. Treat state access like production credentials:

- restrict IAM access to the state bucket;
- never commit local state;
- keep S3 public access blocked;
- retain state locking;
- use separate state paths per environment/region/component;
- rotate K3s credentials if state is exposed.

## Existing release import

If Traefik, cert-manager or Argo CD already exists from the old shell/Helm workflow, import it before the first apply of the corresponding unit:

```bash
cd infrastructure/live/dev/us-east-1/traefik
terragrunt import helm_release.this traefik/traefik

cd ../cert-manager
terragrunt import helm_release.this cert-manager/cert-manager

cd ../argocd
terragrunt import helm_release.this argocd/argocd
```

Review each `terragrunt plan` after import. The new model manages upstream charts directly rather than the removed local wrapper charts.
