data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  traefik_flag = var.enable_traefik ? "" : "--disable traefik"

  kubeconfig_parameter_names = {
    kubernetes_host      = "/k3s/${var.cluster_name}/kubeconfig/server"
    cluster_ca           = "/k3s/${var.cluster_name}/kubeconfig/cluster-ca-data"
    client_certificate   = "/k3s/${var.cluster_name}/kubeconfig/client-certificate-data"
    client_key           = "/k3s/${var.cluster_name}/kubeconfig/client-key-data"
  }

  install_script = templatefile("${path.module}/install.sh.tftpl", {
    cluster_name                 = var.cluster_name
    k3s_version                  = var.k3s_version
    public_ip                    = var.public_ip
    region                       = var.region
    traefik_flag                 = local.traefik_flag
    kubernetes_host_parameter    = local.kubeconfig_parameter_names.kubernetes_host
    cluster_ca_parameter         = local.kubeconfig_parameter_names.cluster_ca
    client_certificate_parameter = local.kubeconfig_parameter_names.client_certificate
    client_key_parameter         = local.kubeconfig_parameter_names.client_key
  })
}

# Terraform creates the Parameter Store keys so their lifecycle, tags and cleanup
# remain declarative. K3s publishes the real values after the service is healthy.
resource "aws_ssm_parameter" "kubernetes_host" {
  name  = local.kubeconfig_parameter_names.kubernetes_host
  type  = "String"
  value = "pending"
  tier  = "Standard"
  tags  = var.tags

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "kubeconfig_credentials" {
  for_each = {
    cluster_ca         = local.kubeconfig_parameter_names.cluster_ca
    client_certificate = local.kubeconfig_parameter_names.client_certificate
    client_key         = local.kubeconfig_parameter_names.client_key
  }

  name  = each.value
  type  = "SecureString"
  value = "pending"
  tier  = "Standard"
  tags  = var.tags

  lifecycle {
    ignore_changes = [value]
  }
}

data "aws_iam_policy_document" "publish_kubeconfig" {
  statement {
    sid     = "PublishK3sKubeconfig"
    effect  = "Allow"
    actions = ["ssm:PutParameter"]

    resources = concat(
      [aws_ssm_parameter.kubernetes_host.arn],
      [for parameter in aws_ssm_parameter.kubeconfig_credentials : parameter.arn],
    )
  }
}

resource "aws_iam_role_policy" "publish_kubeconfig" {
  name   = "${var.cluster_name}-publish-kubeconfig"
  role   = var.instance_role_name
  policy = data.aws_iam_policy_document.publish_kubeconfig.json
}

# K3s lifecycle is independent from EC2 lifecycle. Updating K3s changes this
# SSM association instead of replacing the EC2 instance.
resource "aws_ssm_association" "install" {
  name             = "AWS-RunShellScript"
  association_name = "${var.cluster_name}-k3s-install"

  targets {
    key    = "InstanceIds"
    values = [var.instance_id]
  }

  parameters = {
    commands = local.install_script
  }

  wait_for_success_timeout_seconds = var.wait_for_success_timeout_seconds

  depends_on = [aws_iam_role_policy.publish_kubeconfig]
}

# These reads happen only after the SSM association reports success. They let
# Terragrunt expose kubeconfig and feed the Terraform Helm provider without a
# Makefile, local bootstrap script, or Helm CLI.
data "aws_ssm_parameter" "kubernetes_host" {
  name = aws_ssm_parameter.kubernetes_host.name

  depends_on = [aws_ssm_association.install]
}

data "aws_ssm_parameter" "kubeconfig_credentials" {
  for_each = aws_ssm_parameter.kubeconfig_credentials

  name            = each.value.name
  with_decryption = true

  depends_on = [aws_ssm_association.install]
}
