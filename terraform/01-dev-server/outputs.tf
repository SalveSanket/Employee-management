# =============================================================================
# 01-dev-server: outputs (see them again with: terraform output)
# =============================================================================

output "instance_id" {
  description = "EC2 instance ID of dev1."
  value       = module.server.instance_id
}

output "public_ip" {
  description = "Public IP of dev1 (changes if the server is stopped and started)."
  value       = module.server.public_ip
}

output "private_ip" {
  description = "Private IP of dev1 inside the VPC."
  value       = module.server.private_ip
}

output "ssh_allowed_from" {
  description = "IP range allowed to SSH in."
  value       = local.admin_cidr
}

output "ssh_command" {
  description = "Log in to dev1."
  value       = "ssh -i ~/.ssh/${var.project}-project.pem ec2-user@${module.server.public_ip}"
}

output "bootstrap_check_command" {
  description = "Run on dev1 to confirm the install script finished."
  value       = "cloud-init status --wait && cat /var/log/bootstrap-complete"
}
