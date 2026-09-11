# Shared EC2 compute defaults.
# Keep compute lifecycle independent from K3s configuration/lifecycle.
terraform {
  source = "${get_repo_root()}/infrastructure/modules//ec2"
}

inputs = {
  instance_type       = "t3.medium"
  root_volume_size    = 30
  primary_instance_key = "primary"

  # EC2 nodes are map-driven and created with Terraform for_each. The current
  # repository profile intentionally has one primary node; add map entries here
  # or in an environment override when additional compute nodes are required.
  instances = {
    primary = {}
  }
}
