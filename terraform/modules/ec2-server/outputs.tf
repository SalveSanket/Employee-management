# =============================================================================
# Outputs of the ec2-server module
# =============================================================================

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.this.id
}

output "name" {
  description = "Server name (Name tag)."
  value       = var.name
}

output "public_ip" {
  description = "Public IP. The Elastic IP when one is attached, otherwise the normal public IP (changes on restart)."
  value       = var.associate_elastic_ip ? aws_eip.this[0].public_ip : aws_instance.this.public_ip
}

output "private_ip" {
  description = "Private IP inside the VPC, used for server-to-server traffic."
  value       = aws_instance.this.private_ip
}

output "security_group_id" {
  description = "ID of the server's security group (firewall)."
  value       = aws_security_group.this.id
}

output "ami_id" {
  description = "AMI the server was created from."
  value       = aws_instance.this.ami
}
