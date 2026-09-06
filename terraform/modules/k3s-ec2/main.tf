data "aws_partition" "current" {}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  tags = merge(var.tags, {
    Name = var.cluster_name
  })

  traefik_flag = var.enable_traefik ? "" : "--disable traefik"
}

# Stable public endpoint for the Kubernetes API and Traefik ingress.
resource "aws_eip" "this" {
  domain = "vpc"

  tags = merge(local.tags, {
    Name = "${var.cluster_name}-eip"
  })
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.cluster_name}-node"
  role = aws_iam_role.node.name
  tags = local.tags
}

resource "aws_security_group" "node" {
  name        = "${var.cluster_name}-node"
  description = "K3s node security group"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = "${var.cluster_name}-node"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  for_each = toset(var.ingress_allowed_cidrs)

  security_group_id = aws_security_group.node.id
  description       = "HTTP ingress"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = toset(var.ingress_allowed_cidrs)

  security_group_id = aws_security_group.node.id
  description       = "HTTPS ingress"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "kube_api" {
  for_each = toset(var.api_allowed_cidrs)

  security_group_id = aws_security_group.node.id
  description       = "Kubernetes API"
  cidr_ipv4         = each.value
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.node.id
  description       = "All outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "node" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.node.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  # EIP association supplies the stable public endpoint.
  associate_public_ip_address = false

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    cluster_name = var.cluster_name
    k3s_channel  = var.k3s_channel
    public_ip    = aws_eip.this.public_ip
    traefik_flag = local.traefik_flag
  })

  tags = local.tags

  lifecycle {
    precondition {
      condition     = length(var.api_allowed_cidrs) > 0
      error_message = "api_allowed_cidrs must contain at least one CIDR; refusing to create an unreachable or accidentally open Kubernetes API."
    }
  }
}

resource "aws_eip_association" "this" {
  instance_id   = aws_instance.node.id
  allocation_id = aws_eip.this.id
}
