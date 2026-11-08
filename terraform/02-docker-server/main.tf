# =============================================================================
# 02-docker-server: the application server (docker-node1)
# Runs the app containers (Nginx + Node.js). Ansible deploys to it.
# =============================================================================

locals {
  server_name = "docker-node1"
}

# ---------- Find the shared resources from 00-shared (by tag or name, no copied IDs) ----------

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

# Public half of the internal key: the ansible server logs in with the private half.
# A public key is not secret, so it may be placed in user_data.
data "aws_ssm_parameter" "internal_public_key" {
  name = "/${var.project}/ssh/internal-public-key"
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
  role             = "docker"
  instance_type    = var.instance_type
  root_volume_size = var.root_volume_size

  vpc_id    = data.aws_vpc.main.id
  subnet_id = data.aws_subnet.public.id
  key_name  = data.aws_key_pair.login.key_name

  # Installs everything on first boot (see scripts/install.sh)
  user_data = templatefile("${path.module}/scripts/install.sh", {
    hostname            = local.server_name
    timezone            = var.timezone
    deploy_user         = var.deploy_user
    app_dir             = var.app_dir
    internal_public_key = chomp(data.aws_ssm_parameter.internal_public_key.insecure_value)
  })

  # Fixed public IP: the app URL and the MongoDB Atlas allowlist must not change
  associate_elastic_ip = true

  # The SSH rule for the ansible server is added by 03-ansible-server,
  # because the ansible firewall does not exist yet when this server is built.
  ingress_rules = {
    ssh-admin = {
      description = "SSH from the admin IP"
      port        = 22
      cidr        = local.admin_cidr
    }
    http = {
      description = "Website (Nginx container)"
      port        = 80
      cidr        = var.web_cidr
    }
  }
}
