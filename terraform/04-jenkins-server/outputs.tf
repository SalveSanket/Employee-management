# =============================================================================
# 04-jenkins-server: outputs (see them again with: terraform output)
# =============================================================================

output "instance_id" {
  description = "EC2 instance ID of the jenkins server."
  value       = module.server.instance_id
}

output "public_ip" {
  description = "Elastic IP of the jenkins server (fixed)."
  value       = module.server.public_ip
}

output "private_ip" {
  description = "Private IP inside the VPC."
  value       = module.server.private_ip
}

output "security_group_id" {
  description = "Firewall of the jenkins server."
  value       = module.server.security_group_id
}

output "jenkins_url" {
  description = "Jenkins web UI (open from the admin IP)."
  value       = "http://${module.server.public_ip}:${var.jenkins_port}"
}

output "github_webhook_url" {
  description = "Payload URL for the GitHub webhook (repository Settings > Webhooks)."
  value       = "http://${module.server.public_ip}:${var.jenkins_port}/github-webhook/"
}

output "github_webhook_cidrs" {
  description = "GitHub webhook IP ranges allowed to reach Jenkins."
  value       = local.github_hook_cidrs
}

output "ansible_private_ip" {
  description = "Private IP of the ansible server. Jenkins connects to it over SSH as itadmin."
  value       = data.aws_instance.ansible.private_ip
}

output "ui_allowed_from" {
  description = "IP range allowed to SSH in and open the Jenkins UI."
  value       = local.admin_cidr
}

output "ssh_command" {
  description = "Log in to the jenkins server."
  value       = "ssh -i ~/.ssh/${var.project}-project.pem ec2-user@${module.server.public_ip}"
}

output "initial_admin_password_command" {
  description = "Run on the jenkins server to get the password for the first login (setup wizard)."
  value       = "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
}

output "bootstrap_check_command" {
  description = "Run on the jenkins server to confirm the install script finished."
  value       = "sudo cloud-init status --wait && cat /var/log/bootstrap-complete"
}
