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

variable "instance_id" {
  description = "Existing EC2 instance ID that will run K3s."
  type        = string
}

variable "instance_role_name" {
  description = "IAM role attached to the EC2 instance. K3s adds only the scoped permission required to publish kubeconfig material."
  type        = string
}

variable "public_ip" {
  description = "Stable public IP added to the K3s API TLS SAN list."
  type        = string
}

variable "k3s_version" {
  description = "Exact K3s release to install."
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+k3s[0-9]+$", var.k3s_version))
    error_message = "k3s_version must be an exact K3s release such as v1.36.4+k3s1."
  }
}

variable "enable_traefik" {
  description = "Whether to keep the K3s bundled Traefik controller enabled."
  type        = bool
  default     = false
}

variable "wait_for_success_timeout_seconds" {
  description = "Maximum time Terraform waits for the SSM association to report Success."
  type        = number
  default     = 900

  validation {
    condition     = var.wait_for_success_timeout_seconds >= 60
    error_message = "wait_for_success_timeout_seconds must be at least 60 seconds."
  }
}

variable "tags" {
  description = "Common tags passed by Terragrunt."
  type        = map(string)
  default     = {}
}
