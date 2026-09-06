variable "name" {
  description = "Name used for the EC2 node and supporting resources."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the EC2 security group."
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the EC2 instance."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size >= 20
    error_message = "root_volume_size must be at least 20 GiB."
  }
}

variable "ami_ssm_parameter_name" {
  description = "AWS SSM public parameter containing the AMI ID."
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

variable "ingress_rules" {
  description = "IPv4 ingress rules applied to the EC2 node security group."
  type = map(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_ipv4   = string
  }))
  default = {}
}

variable "additional_iam_policy_arns" {
  description = "Additional managed IAM policies to attach to the EC2 instance role."
  type        = set(string)
  default     = []
}

variable "tags" {
  description = "Common AWS tags."
  type        = map(string)
  default     = {}
}
