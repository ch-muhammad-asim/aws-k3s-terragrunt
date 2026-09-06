include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "component" {
  path           = "${dirname(find_in_parent_folders("root.hcl"))}/_common/k3s.hcl"
  merge_strategy = "deep"
}

locals {
  # Anchor sibling dependencies to the region config instead of brittle ../ paths.
  # The environment hierarchy can grow or move without changing this dependency.
  region_dir = dirname(find_in_parent_folders("region.hcl"))

  operator_cidr = get_env(
    "TG_OPERATOR_CIDR",
    "${trimspace(run_cmd("--terragrunt-quiet", "curl", "-fsS", "https://checkip.amazonaws.com"))}/32",
  )
}

dependency "vpc" {
  config_path = "${local.region_dir}/vpc"

  mock_outputs = {
    vpc_id            = "vpc-00000000000000000"
    public_subnet_ids = ["subnet-00000000000000000"]
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  cluster_name = include.root.locals.cluster_name
  vpc_id       = dependency.vpc.outputs.vpc_id
  subnet_id    = dependency.vpc.outputs.public_subnet_ids[0]

  api_allowed_cidrs = [local.operator_cidr]
}
