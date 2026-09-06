# Shared EC2 compute defaults.
# Keep compute lifecycle independent from K3s configuration/lifecycle.
terraform {
  source = "${get_repo_root()}/infrastructure/modules//ec2"
}

inputs = {
  instance_type    = "t3.medium"
  root_volume_size = 30
}
