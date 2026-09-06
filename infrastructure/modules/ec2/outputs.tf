output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "Stable Elastic IP associated with the EC2 instance."
  value       = aws_eip.this.public_ip
}

output "private_ip" {
  description = "Private IP of the EC2 instance."
  value       = aws_instance.this.private_ip
}

output "security_group_id" {
  description = "EC2 node security group ID."
  value       = aws_security_group.this.id
}

output "iam_role_name" {
  description = "IAM role attached to the EC2 instance."
  value       = aws_iam_role.this.name
}

output "ssm_session_command" {
  description = "Command for opening an SSM shell session."
  value       = "aws ssm start-session --region ${var.region} --target ${aws_instance.this.id}"
}
