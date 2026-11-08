# =============================================================================
# 01-dev-server: the developer machine (dev1)
# Writes code and pushes it to GitHub. Not part of the running app.
# =============================================================================

locals {
  server_name = "dev1"
}

# ---------- Find the shared resources from 00-shared (by tag, no copied IDs) ----------

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

# Fails early with a clear error if 00-shared has not been applied
data "aws_key_pair" "login" {
  key_name = "${var.project}-login-key"
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
  role             = "dev"
  instance_type    = var.instance_type
  root_volume_size = var.root_volume_size

  vpc_id    = data.aws_vpc.main.id
  subnet_id = data.aws_subnet.public.id
  key_name  = data.aws_key_pair.login.key_name

  # Installs everything on first boot (see scripts/install.sh)
  user_data = templatefile("${path.module}/scripts/install.sh", {
    hostname       = local.server_name
    timezone       = var.timezone
    node_major     = var.node_major_version
    repo_url       = var.repo_url
    git_user_name  = var.git_user_name
    git_user_email = var.git_user_email
  })

  # dev1 is only used by you over SSH, so it needs no fixed IP
  associate_elastic_ip = false

  ingress_rules = {
    ssh-admin = {
      description = "SSH from the admin IP"
      port        = 22
      cidr        = local.admin_cidr
    }
  }
}
