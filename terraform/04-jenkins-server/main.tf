# =============================================================================
# 04-jenkins-server: the CI/CD server (jenkins)
# Installs Jenkins and its build dependencies only.
# Jenkins itself (unlock, plugins, credentials, jobs) is set up manually in the UI.
# =============================================================================

locals {
  server_name = "jenkins"
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

# ---------- Find the ansible server from 03-ansible-server (by tag) ----------

data "aws_security_group" "ansible" {
  vpc_id = data.aws_vpc.main.id

  tags = {
    Name    = "${var.project}-${var.ansible_server_name}-sg"
    Project = var.project
  }
}

# Only for the outputs: the address you enter in the pipeline settings
data "aws_instance" "ansible" {
  filter {
    name   = "tag:Name"
    values = [var.ansible_server_name]
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

# ---------- GitHub's official webhook IP ranges ----------

data "http" "github_meta" {
  count = var.allow_github_webhooks ? 1 : 0
  url   = "https://api.github.com/meta"

  request_headers = {
    Accept = "application/vnd.github+json"
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && can(jsondecode(self.response_body).hooks)
      error_message = "Could not read GitHub webhook IP ranges from api.github.com/meta. Retry, or set allow_github_webhooks = false."
    }
  }
}

locals {
  admin_cidr = var.admin_cidr != null ? var.admin_cidr : "${chomp(data.http.my_ip[0].response_body)}/32"

  # IPv4 ranges only (the VPC has no IPv6)
  github_hook_cidrs = var.allow_github_webhooks ? sort([
    for cidr in jsondecode(data.http.github_meta[0].response_body).hooks : cidr if !strcontains(cidr, ":")
  ]) : []

  github_hook_rules = {
    for index, cidr in local.github_hook_cidrs : "github-webhook-${index + 1}" => {
      description = "GitHub webhooks (${cidr})"
      port        = var.jenkins_port
      cidr        = cidr
    }
  }

  admin_rules = {
    ssh-admin = {
      description = "SSH from the admin IP"
      port        = 22
      cidr        = local.admin_cidr
    }
    jenkins-ui-admin = {
      description = "Jenkins UI from the admin IP"
      port        = var.jenkins_port
      cidr        = local.admin_cidr
    }
  }
}

# ---------- The server ----------

module "server" {
  source = "../modules/ec2-server"

  project          = var.project
  name             = local.server_name
  role             = "jenkins"
  instance_type    = var.instance_type
  root_volume_size = var.root_volume_size

  vpc_id    = data.aws_vpc.main.id
  subnet_id = data.aws_subnet.public.id
  key_name  = data.aws_key_pair.login.key_name

  # Installs Jenkins and its dependencies on first boot (see scripts/install.sh)
  user_data = templatefile("${path.module}/scripts/install.sh", {
    hostname     = local.server_name
    timezone     = var.timezone
    java_major   = var.java_major_version
    node_major   = var.node_major_version
    jenkins_port = var.jenkins_port
  })

  # Fixed public IP: the Jenkins URL and the GitHub webhook URL must not change
  associate_elastic_ip = true

  ingress_rules = merge(local.admin_rules, local.github_hook_rules)
}

# ---------- Allow Jenkins (and only Jenkins) to SSH into the ansible server ----------

# Added to the ansible server's firewall. Destroying this folder removes the rule again.
resource "aws_vpc_security_group_ingress_rule" "ansible_ssh_from_jenkins" {
  security_group_id            = data.aws_security_group.ansible.id
  description                  = "SSH from the jenkins server"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = module.server.security_group_id

  tags = {
    Name = "${var.project}-${var.ansible_server_name}-ssh-from-jenkins"
  }
}
