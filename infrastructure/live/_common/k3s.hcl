# Shared K3s component defaults.
# Keep platform versions and common sizing in one place instead of duplicating
# them across every environment and region.
terraform {
  source = "${get_repo_root()}/infrastructure/modules//k3s-ec2"
}

inputs = {
  instance_type    = "t3.medium"
  root_volume_size = 30

  # Exact release pin for reproducible node rebuilds.
  k3s_version = "v1.36.4+k3s1"

  ingress_allowed_cidrs = ["0.0.0.0/0"]

  # Traefik is managed separately by the pinned Helm deployment.
  enable_traefik = false
}
