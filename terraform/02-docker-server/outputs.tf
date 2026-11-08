# =============================================================================
# 02-docker-server: outputs (see them again with: terraform output)
# =============================================================================

output "instance_id" {
  description = "EC2 instance ID of docker-node1."
  value       = module.server.instance_id
}

output "public_ip" {
  description = "Elastic IP of docker-node1 (fixed). Allow this IP in MongoDB Atlas Network Access."
  value       = module.server.public_ip
}

output "private_ip" {
  description = "Private IP inside the VPC. The ansible server connects to this address."
  value       = module.server.private_ip
}

output "security_group_id" {
  description = "Firewall of docker-node1. 03-ansible-server adds its SSH rule here."
  value       = module.server.security_group_id
}

output "app_url" {
  description = "Website address once the app is deployed."
  value       = "http://${module.server.public_ip}"
}

output "ssh_allowed_from" {
  description = "IP range allowed to SSH in as ec2-user."
  value       = local.admin_cidr
}

output "ssh_command" {
  description = "Log in to docker-node1."
  value       = "ssh -i ~/.ssh/${var.project}-project.pem ec2-user@${module.server.public_ip}"
}

output "deploy_user" {
  description = "User the ansible server logs in as (internal key only)."
  value       = var.deploy_user
}

output "bootstrap_check_command" {
  description = "Run on docker-node1 to confirm the install script finished."
  value       = "cloud-init status --wait && cat /var/log/bootstrap-complete"
}
