# =============================================================================
# 00-shared: SSH keys
#
# 1. Login key    : you -> any server (saved on your Mac, never in Git)
# 2. Internal key : jenkins -> ansible -> docker-node1 (stored encrypted in SSM)
#
# Note: generated private keys are also kept in the Terraform state file,
# which is why terraform.tfstate stays private and is ignored by Git.
# =============================================================================

# ---------- 1. Login key ----------

resource "tls_private_key" "login" {
  algorithm = "ED25519" # modern, short and secure
}

# Registers the public half in AWS so servers accept it (user ec2-user)
resource "aws_key_pair" "login" {
  key_name   = "${var.project}-login-key"
  public_key = tls_private_key.login.public_key_openssh

  tags = {
    Name = "${var.project}-login-key"
  }
}

# Saves the private half on your Mac, readable only by you (chmod 400)
resource "local_sensitive_file" "login_private_key" {
  filename             = pathexpand(var.login_key_path)
  content              = tls_private_key.login.private_key_openssh
  file_permission      = "0400"
  directory_permission = "0700"
}

# ---------- 2. Internal key (server to server) ----------

# RSA 4096 for the widest compatibility (OpenSSH, Ansible, Jenkins SSH Agent)
resource "tls_private_key" "internal" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Private half: encrypted (SecureString, AWS managed KMS key).
# The ansible server reads it at boot through its IAM role; you add it to Jenkins.
resource "aws_ssm_parameter" "internal_private_key" {
  name        = "/${var.project}/ssh/internal-private-key"
  description = "Private SSH key used by jenkins and ansible to reach other servers"
  type        = "SecureString"
  tier        = "Standard"
  value       = tls_private_key.internal.private_key_openssh
}

# Public half: not secret. Server folders put it in itadmin's authorized_keys.
resource "aws_ssm_parameter" "internal_public_key" {
  name        = "/${var.project}/ssh/internal-public-key"
  description = "Public SSH key accepted by the itadmin user on ansible and docker-node1"
  type        = "String"
  tier        = "Standard"
  value       = tls_private_key.internal.public_key_openssh
}
