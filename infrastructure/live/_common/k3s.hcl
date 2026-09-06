# Shared K3s configuration defaults.
# K3s is installed on an existing EC2 instance through AWS Systems Manager.
terraform {
  source = "${get_repo_root()}/infrastructure/modules//k3s"
}

inputs = {
  # Exact release pin for reproducible upgrades.
  k3s_version = "v1.36.4+k3s1"

  # Traefik is managed separately by the pinned Helm deployment.
  enable_traefik = false

  # Fail Terraform/Terragrunt if the K3s SSM association cannot converge.
  wait_for_success_timeout_seconds = 900
}
