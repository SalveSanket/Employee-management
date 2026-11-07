# =============================================================================
# ec2-server module
# One EC2 server with its own security group (firewall) and an optional
# Elastic IP. The software is installed by the user_data script on first boot.
# =============================================================================

locals {
  base_name = "${var.project}-${var.name}"

  # Every resource gets these tags. Other folders find servers by Project + Role.
  common_tags = merge(var.tags, {
    Project   = var.project
    Role      = var.role
    ManagedBy = "terraform"
  })

  ami_id = var.ami_id != null ? var.ami_id : data.aws_ssm_parameter.al2023[0].insecure_value

  # CPU credit settings only exist for burstable (t2, t3, ...) instance types
  is_burstable = startswith(var.instance_type, "t")
}

# ---------- Operating system image ----------

# Latest Amazon Linux 2023, published by AWS in a public SSM parameter.
# Used only when no ami_id is given.
data "aws_ssm_parameter" "al2023" {
  count = var.ami_id == null ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---------- Firewall ----------

resource "aws_security_group" "this" {
  name        = "${local.base_name}-sg"
  description = "Firewall for ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = "${local.base_name}-sg" })
}

# One resource per inbound rule, so adding or removing a rule never touches the others
resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = var.ingress_rules

  security_group_id            = aws_security_group.this.id
  description                  = each.value.description
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.port
  to_port                      = each.value.port
  cidr_ipv4                    = each.value.cidr
  referenced_security_group_id = each.value.source_security_group_id

  tags = merge(local.common_tags, { Name = "${local.base_name}-${each.key}" })
}

# Outbound: the server must reach package mirrors, GitHub, Docker Hub and MongoDB Atlas
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.common_tags, { Name = "${local.base_name}-egress-all" })
}

# ---------- Server ----------

resource "aws_instance" "this" {
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  key_name                    = var.key_name
  iam_instance_profile        = var.iam_instance_profile
  associate_public_ip_address = true

  # Bootstrap: cloud-init runs this script once, on the first boot.
  # If the script changes, the server is rebuilt from scratch (immutable infrastructure).
  user_data                   = var.user_data
  user_data_replace_on_change = true

  # Instance metadata: allow only the secure version (IMDSv2)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Encrypted SSD disk, deleted together with the server
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  # "standard" CPU credits: no surprise charges for burst CPU usage
  dynamic "credit_specification" {
    for_each = local.is_burstable ? [1] : []
    content {
      cpu_credits = "standard"
    }
  }

  tags        = merge(local.common_tags, { Name = var.name })
  volume_tags = merge(local.common_tags, { Name = "${local.base_name}-root" })

  lifecycle {
    # A new Amazon Linux release must not rebuild a running server by surprise
    ignore_changes = [ami]
  }
}

# ---------- Fixed public IP (optional) ----------

# The Elastic IP moves to the new server when the server is rebuilt,
# so URLs, webhooks and the MongoDB Atlas allowlist keep working.
resource "aws_eip" "this" {
  count = var.associate_elastic_ip ? 1 : 0

  domain   = "vpc"
  instance = aws_instance.this.id

  tags = merge(local.common_tags, { Name = "${local.base_name}-eip" })
}
