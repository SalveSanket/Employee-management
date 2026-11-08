# =============================================================================
# 00-shared: outputs (printed after apply; see them again with: terraform output)
# =============================================================================

output "region" {
  description = "AWS region."
  value       = var.aws_region
}

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC IP range."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_id" {
  description = "Public subnet ID."
  value       = aws_subnet.public.id
}

output "availability_zone" {
  description = "Availability zone of the subnet."
  value       = aws_subnet.public.availability_zone
}

output "login_key_name" {
  description = "Name of the EC2 key pair for SSH login."
  value       = aws_key_pair.login.key_name
}

output "login_key_path" {
  description = "Login private key on this machine."
  value       = local_sensitive_file.login_private_key.filename
}

output "internal_private_key_parameter" {
  description = "SSM parameter holding the internal private key (encrypted)."
  value       = aws_ssm_parameter.internal_private_key.name
}

output "internal_public_key_parameter" {
  description = "SSM parameter holding the internal public key."
  value       = aws_ssm_parameter.internal_public_key.name
}

output "ssh_command_template" {
  description = "How to log in to any server once it exists."
  value       = "ssh -i ${local_sensitive_file.login_private_key.filename} ec2-user@<server-public-ip>"
}
