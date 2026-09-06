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

variable "k3s_version" {
  description = "Exact K3s release to install. Pin this for reproducible deployments, for example v1.36.4+k3s1."
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+k3s[0-9]+$", var.k3s_version))
    error_message = "k3s_version must be an exact K3s release such as v1.36.4+k3s1."
  }
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
