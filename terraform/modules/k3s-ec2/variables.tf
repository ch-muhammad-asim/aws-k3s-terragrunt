variable "cluster_name" {
  description = "K3s cluster/node name."
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
  description = "VPC ID."
  type        = string
}

variable "subnet_id" {
  description = "Public subnet ID for the K3s node."
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
}

variable "k3s_channel" {
  description = "K3s install channel, for example stable or latest."
  type        = string
  default     = "stable"
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach Kubernetes API TCP/6443."
  type        = list(string)
  default     = []
}

variable "ingress_allowed_cidrs" {
  description = "CIDRs allowed to reach HTTP/HTTPS ingress."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_traefik" {
  description = "Keep K3s bundled Traefik ingress controller enabled."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
