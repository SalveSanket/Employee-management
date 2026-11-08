# =============================================================================
# 03-ansible-server: the control node (ansible)
# Receives the app package from Jenkins and deploys it to docker-node1.
# =============================================================================

locals {
  server_name = "ansible"
}

# ---------- Find the shared resources from 00-shared ----------

data "aws_vpc" "main" {
  tags = {
    Name    = "${var.project}-vpc"
    Project = var.project
  }
}

data "aws_subnet" "public" {
  vpc_id = data.aws_vpc.main.id

  tags = {
    Tier    = "public"
    Project = var.project
  }
}

data "aws_key_pair" "login" {
  key_name = "${var.project}-login-key"
}

# Public half of the internal key: Jenkins logs in to this server with the private half
data "aws_ssm_parameter" "internal_public_key" {
  name = "/${var.project}/ssh/internal-public-key"
}

# ---------- Find docker-node1 from 02-docker-server (by tag) ----------

# Fails with a clear error if docker-node1 does not exist or is not running
data "aws_instance" "docker" {
  filter {
    name   = "tag:Name"
    values = [var.docker_server_name]
  }

  filter {
    name   = "tag:Project"
    values = [var.project]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

data "aws_security_group" "docker" {
  vpc_id = data.aws_vpc.main.id

  tags = {
    Name    = "${var.project}-${var.docker_server_name}-sg"
    Project = var.project
  }
}

# ---------- Your current public IP (only when admin_cidr is not set) ----------

data "http" "my_ip" {
  count = var.admin_cidr == null ? 1 : 0
  url   = "https://checkip.amazonaws.com"

  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && can(cidrhost("${chomp(self.response_body)}/32", 0))
      error_message = "Could not detect your public IP. Set admin_cidr in terraform.tfvars, for example \"203.0.113.10/32\"."
    }
  }
}

locals {
  admin_cidr = var.admin_cidr != null ? var.admin_cidr : "${chomp(data.http.my_ip[0].response_body)}/32"
}

# ---------- The server ----------

module "server" {
  source = "../modules/ec2-server"

  project          = var.project
  name             = local.server_name
  role             = "ansible"
  instance_type    = var.instance_type
  root_volume_size = var.root_volume_size

  vpc_id    = data.aws_vpc.main.id
  subnet_id = data.aws_subnet.public.id
  key_name  = data.aws_key_pair.login.key_name

  # Lets the server read the internal private key from SSM at boot
  iam_instance_profile = aws_iam_instance_profile.ansible.name

  # Installs everything on first boot (see scripts/install.sh).
  # docker-node1's private IP is part of the script, so if docker-node1 is rebuilt
  # with a new IP, this server is rebuilt too and always has the correct inventory.
  user_data = templatefile("${path.module}/scripts/install.sh", {
    hostname            = local.server_name
    timezone            = var.timezone
    region              = var.aws_region
    deploy_user         = var.deploy_user
    private_key_param   = data.aws_ssm_parameter.internal_private_key.name
    internal_public_key = chomp(data.aws_ssm_parameter.internal_public_key.insecure_value)
    docker_host_name    = var.docker_server_name
    docker_host_ip      = data.aws_instance.docker.private_ip
    project_dir         = var.project_dir
    staging_dir         = var.staging_dir
  })

  associate_elastic_ip = false

  # SSH from Jenkins is added by 04-jenkins-server (same pattern as below)
  ingress_rules = {
    ssh-admin = {
      description = "SSH from the admin IP"
      port        = 22
      cidr        = local.admin_cidr
    }
  }
}

# ---------- Allow this server (and only this server) to SSH into docker-node1 ----------

# Added to docker-node1's firewall. Destroying this folder removes the rule again.
resource "aws_vpc_security_group_ingress_rule" "docker_ssh_from_ansible" {
  security_group_id            = data.aws_security_group.docker.id
  description                  = "SSH from the ansible server"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = module.server.security_group_id

  tags = {
    Name = "${var.project}-${var.docker_server_name}-ssh-from-ansible"
  }
}
