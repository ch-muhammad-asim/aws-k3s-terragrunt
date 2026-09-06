locals {
  env_vars    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.env_vars.locals.environment
  cluster_name = local.env_vars.locals.cluster_name
  aws_region   = local.region_vars.locals.aws_region
  account_id   = get_aws_account_id()

  repo_dir    = dirname(dirname(find_in_parent_folders("root.hcl")))
  modules_dir = "${local.repo_dir}/terraform/modules"

  state_bucket = get_env(
    "TG_STATE_BUCKET",
    "k3s-terraform-state-${local.account_id}-${local.aws_region}",
  )

  common_tags = {
    Environment = local.environment
    Terraform   = "true"
    ManagedBy   = "terragrunt"
    Project     = local.cluster_name
  }
}

remote_state {
  backend = "s3"

  config = {
    bucket       = local.state_bucket
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = local.aws_region
    encrypt      = true
    use_lockfile = true

    s3_bucket_tags = local.common_tags
  }

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF_PROVIDER
    provider "aws" {
      region = "${local.aws_region}"

      default_tags {
        tags = {
          Environment = "${local.environment}"
          Terraform   = "true"
          ManagedBy   = "terragrunt"
          Project     = "${local.cluster_name}"
        }
      }
    }
  EOF_PROVIDER
}

inputs = {
  environment = local.environment
  region      = local.aws_region
  tags        = local.common_tags
}
