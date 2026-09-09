# Architecture diagrams

This directory contains rendered architecture assets used by the repository documentation.

## K3s platform overview

![K3s on AWS platform architecture](k3s-platform-overview.svg)

The SVG represents the current repository profile:

- Terraform/Terragrunt provision AWS infrastructure and keep remote state in S3.
- VPC, EC2, and K3s are separate lifecycle/state boundaries.
- AWS Systems Manager installs and configures K3s on the existing EC2 instance.
- the single K3s node runs control-plane and workload components.
- K3s bundled Traefik is disabled; Traefik is installed and version-pinned through Helm.
- cert-manager and Argo CD are also Helm-managed platform services.
- the current topology is single-node and therefore does not provide node-level high availability.

The SVG is intentionally committed as a repository asset rather than generated at page-render time, so GitHub, documentation sites, and downstream consumers render the same reviewed architecture image.
