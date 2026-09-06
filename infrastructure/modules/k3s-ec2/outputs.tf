output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.node.id
}

output "public_ip" {
  description = "Stable Elastic IP for K3s API and ingress."
  value       = aws_eip.this.public_ip
}

output "private_ip" {
  description = "Private IP of the K3s EC2 instance."
  value       = aws_instance.node.private_ip
}

output "security_group_id" {
  description = "K3s node security group ID."
  value       = aws_security_group.node.id
}

output "kubernetes_api" {
  description = "Kubernetes API endpoint."
  value       = "https://${aws_eip.this.public_ip}:6443"
}

output "ssm_session_command" {
  description = "Command for opening an SSM shell session."
  value       = "aws ssm start-session --target ${aws_instance.node.id}"
}

output "k3s_version" {
  description = "Exact K3s version configured for installation."
  value       = var.k3s_version
}
