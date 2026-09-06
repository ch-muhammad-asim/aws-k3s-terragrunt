locals {
  traefik_flag = var.enable_traefik ? "" : "--disable traefik"

  install_script = templatefile("${path.module}/install.sh.tftpl", {
    cluster_name = var.cluster_name
    k3s_version  = var.k3s_version
    public_ip    = var.public_ip
    traefik_flag = local.traefik_flag
  })
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
}
