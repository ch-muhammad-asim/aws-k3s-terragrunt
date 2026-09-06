include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${include.root.locals.modules_dir}//k3s-ec2"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id            = "vpc-00000000000000000"
    public_subnet_ids = ["subnet-00000000000000000"]
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

locals {
  operator_cidr = get_env(
    "TG_OPERATOR_CIDR",
    "${trimspace(run_cmd("--terragrunt-quiet", "curl", "-fsS", "https://checkip.amazonaws.com"))}/32",
  )

  # Pinned exact release for reproducible builds.
  # Verified against the upstream K3s latest release on 2026-09-06.
  k3s_version = "v1.36.4+k3s1"
}

inputs = {
  cluster_name = include.root.locals.cluster_name
  vpc_id       = dependency.vpc.outputs.vpc_id
  subnet_id    = dependency.vpc.outputs.public_subnet_ids[0]

  instance_type    = "t3.medium"
  root_volume_size = 30

  # IMPORTANT: exact K3s version installed by user_data.sh.tftpl.
  # Do not replace this with the moving "stable"/"latest" channel if you want
  # identical rebuilds.
  k3s_version = local.k3s_version

  api_allowed_cidrs     = [local.operator_cidr]
  ingress_allowed_cidrs = ["0.0.0.0/0"]

  enable_traefik = true
}
