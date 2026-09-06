output "k3s_version" {
  description = "Exact K3s version configured for installation."
  value       = var.k3s_version
}

output "kubernetes_api" {
  description = "Kubernetes API endpoint."
  value       = "https://${var.public_ip}:6443"
}

output "ssm_association_id" {
  description = "SSM association responsible for K3s installation/upgrades."
  value       = aws_ssm_association.install.association_id
}
