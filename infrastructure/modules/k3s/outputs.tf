locals {
  kubeconfig = yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = var.cluster_name
      cluster = {
        server                     = data.aws_ssm_parameter.kubernetes_host.value
        "certificate-authority-data" = data.aws_ssm_parameter.kubeconfig_credentials["cluster_ca"].value
      }
    }]
    users = [{
      name = var.cluster_name
      user = {
        "client-certificate-data" = data.aws_ssm_parameter.kubeconfig_credentials["client_certificate"].value
        "client-key-data"         = data.aws_ssm_parameter.kubeconfig_credentials["client_key"].value
      }
    }]
    contexts = [{
      name = var.cluster_name
      context = {
        cluster = var.cluster_name
        user    = var.cluster_name
      }
    }]
    "current-context" = var.cluster_name
  })
}

output "k3s_version" {
  description = "Exact K3s version configured for installation."
  value       = var.k3s_version
}

output "kubernetes_api" {
  description = "Kubernetes API endpoint."
  value       = data.aws_ssm_parameter.kubernetes_host.value
}

output "cluster_ca_certificate_data" {
  description = "Base64-encoded Kubernetes cluster CA used by downstream Terragrunt Helm units."
  value       = data.aws_ssm_parameter.kubeconfig_credentials["cluster_ca"].value
  sensitive   = true
}

output "client_certificate_data" {
  description = "Base64-encoded Kubernetes client certificate used by downstream Terragrunt Helm units."
  value       = data.aws_ssm_parameter.kubeconfig_credentials["client_certificate"].value
  sensitive   = true
}

output "client_key_data" {
  description = "Base64-encoded Kubernetes client key used by downstream Terragrunt Helm units."
  value       = data.aws_ssm_parameter.kubeconfig_credentials["client_key"].value
  sensitive   = true
}

output "kubeconfig" {
  description = "Complete kubeconfig. Retrieve with `terragrunt output -raw kubeconfig`."
  value       = local.kubeconfig
  sensitive   = true
}

output "kubeconfig_parameter_names" {
  description = "SSM Parameter Store names containing the K3s API/client material."
  value       = local.kubeconfig_parameter_names
}

output "ssm_association_id" {
  description = "SSM association responsible for K3s installation/upgrades."
  value       = aws_ssm_association.install.association_id
}
