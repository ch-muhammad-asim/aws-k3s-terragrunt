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
}

inputs = {
  cluster_name = include.root.locals.cluster_name
  vpc_id       = dependency.vpc.outputs.vpc_id
  subnet_id    = dependency.vpc.outputs.public_subnet_ids[0]

  instance_type    = "t3.medium"
  root_volume_size = 30
  k3s_channel      = "stable"

  api_allowed_cidrs     = [local.operator_cidr]
  ingress_allowed_cidrs = ["0.0.0.0/0"]

  enable_traefik = true
}
