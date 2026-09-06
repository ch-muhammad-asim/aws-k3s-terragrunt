# Repository layout and scaling model

The repository separates reusable Terraform modules from live Terragrunt configuration and keeps environment/region leaf units intentionally small.

```text
infrastructure/
├── modules/
│   ├── vpc/
│   └── k3s-ec2/
└── live/
    ├── root.hcl
    ├── _common/
    │   ├── vpc.hcl
    │   └── k3s.hcl
    └── dev/
        ├── env.hcl
        └── us-east-1/
            ├── region.hcl
            ├── vpc/terragrunt.hcl
            └── k3s/terragrunt.hcl
```

## Design rules

1. **Modules are immutable building blocks.** Environment-specific values never belong under `infrastructure/modules`.
2. **Shared component defaults live once.** Versions, baseline instance sizing and common component configuration are kept under `infrastructure/live/_common`.
3. **Leaf units only wire dependencies and overrides.** A new environment or region should not duplicate entire component configurations.
4. **No brittle parent traversal for dependencies.** The K3s unit discovers its region directory from `region.hcl` and resolves the VPC sibling from that anchor. There is no `../vpc` or multi-level `../../..` dependency path.
5. **Resource names include environment and region.** This prevents account-global resources such as IAM roles from colliding when the same environment is deployed in multiple regions.
6. **Operators run commands from the repository root.** `Makefile` and scripts centralize path construction so documentation and CI jobs do not embed deep environment-specific paths.

## Add another region

Create only the region metadata and thin leaf units:

```text
infrastructure/live/dev/eu-west-1/
├── region.hcl
├── vpc/terragrunt.hcl
└── k3s/terragrunt.hcl
```

The region file contains:

```hcl
locals {
  aws_region = "eu-west-1"
}
```

The VPC and K3s leaf units use the same include pattern as `dev/us-east-1`; override CIDRs or sizing only when that region differs.

Run it from the repository root:

```bash
make plan ENV=dev REGION=eu-west-1
make apply ENV=dev REGION=eu-west-1
make kubeconfig ENV=dev REGION=eu-west-1
```

## Add another environment

Create an environment file such as:

```text
infrastructure/live/prod/env.hcl
```

```hcl
locals {
  environment  = "prod"
  project_name = "k3s"
}
```

Then add the required region leaf units beneath `prod/<region>/`.

## CI/CD convention

CI should pass environment and region as parameters rather than checking in separate scripts for every target:

```bash
make plan ENV="$ENVIRONMENT" REGION="$AWS_REGION"
```

The same interface works locally, in GitHub Actions, or in another CI system.
