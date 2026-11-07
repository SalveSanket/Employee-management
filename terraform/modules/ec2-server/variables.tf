# =============================================================================
# Inputs of the ec2-server module
# =============================================================================

# ---------- Naming and tags ----------

variable "project" {
  description = "Project name. Used as a prefix for resource names and as the Project tag."
  type        = string
  default     = "emp"
}

variable "name" {
  description = "Server name, for example docker-node1. Becomes the Name tag and the hostname."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name))
    error_message = "name may contain only lowercase letters, numbers and hyphens."
  }
}

variable "role" {
  description = "Server role: dev, jenkins, ansible or docker. Other folders find this server by the Role tag."
  type        = string

  validation {
    condition     = contains(["dev", "jenkins", "ansible", "docker"], var.role)
    error_message = "role must be one of: dev, jenkins, ansible, docker."
  }
}

variable "tags" {
  description = "Extra tags added to every resource of this server."
  type        = map(string)
  default     = {}
}

# ---------- Server ----------

variable "instance_type" {
  description = "EC2 instance size, for example t2.micro or t3.small."
  type        = string
  default     = "t2.micro"
}

variable "ami_id" {
  description = "AMI to use. Leave null to use the latest Amazon Linux 2023 (x86_64)."
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Size of the root disk in GB (encrypted gp3)."
  type        = number
  default     = 10

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GB (Amazon Linux 2023 minimum)."
  }
}

variable "user_data" {
  description = "Bootstrap script (install.sh). cloud-init runs it once, on the first boot, as root."
  type        = string
  default     = ""
}

variable "iam_instance_profile" {
  description = "IAM instance profile name, if the server needs AWS permissions (for example to read SSM). Null = none."
  type        = string
  default     = null
}

variable "associate_elastic_ip" {
  description = "Attach a fixed public IP (Elastic IP) that stays the same when the server restarts or is rebuilt."
  type        = bool
  default     = false
}

# ---------- Network ----------

variable "vpc_id" {
  description = "VPC where the server and its security group are created."
  type        = string
}

variable "subnet_id" {
  description = "Public subnet for the server."
  type        = string
}

variable "key_name" {
  description = "Name of the EC2 key pair used for SSH login."
  type        = string
}

variable "ingress_rules" {
  description = <<-EOT
    Inbound firewall rules. The map key is a short rule name.
    Each rule must set exactly one source: cidr (an IP range) or source_security_group_id (another server).
  EOT
  type = map(object({
    description              = string
    port                     = number
    protocol                 = optional(string, "tcp")
    cidr                     = optional(string)
    source_security_group_id = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for rule in values(var.ingress_rules) :
      (rule.cidr == null) != (rule.source_security_group_id == null)
    ])
    error_message = "Each ingress rule needs exactly one of cidr or source_security_group_id."
  }
}
