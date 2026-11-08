# =============================================================================
# 03-ansible-server: outputs (see them again with: terraform output)
# =============================================================================

output "instance_id" {
  description = "EC2 instance ID of the ansible server."
  value       = module.server.instance_id
}

output "public_ip" {
  description = "Public IP of the ansible server (changes if the server is stopped and started)."
  value       = module.server.public_ip
}

output "private_ip" {
  description = "Private IP inside the VPC. Jenkins connects to this address."
  value       = module.server.private_ip
}

output "security_group_id" {
  description = "Firewall of the ansible server. 04-jenkins-server adds its SSH rule here."
  value       = module.server.security_group_id
}

output "iam_role_name" {
  description = "IAM role of the ansible server (can read only the internal private key)."
  value       = aws_iam_role.ansible.name
}

output "managed_docker_host" {
  description = "Server Ansible deploys to."
  value       = "${var.docker_server_name} (${data.aws_instance.docker.private_ip})"
}

output "ssh_allowed_from" {
  description = "IP range allowed to SSH in as ec2-user."
  value       = local.admin_cidr
}

output "ssh_command" {
  description = "Log in to the ansible server."
  value       = "ssh -i ~/.ssh/${var.project}-project.pem ec2-user@${module.server.public_ip}"
}

output "bootstrap_check_command" {
  description = "Run on the ansible server to confirm the install script finished."
  value       = "cloud-init status --wait && cat /var/log/bootstrap-complete"
}

output "ansible_ping_command" {
  description = "Run on the ansible server to test the connection to docker-node1."
  value       = "sudo su - ${var.deploy_user} -c 'ansible docker -m ping'"
}
