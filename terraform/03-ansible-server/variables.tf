# =============================================================================
# 03-ansible-server: inputs (all have safe defaults; override in terraform.tfvars)
# =============================================================================

variable "aws_region" {
  description = "AWS region. Must match 00-shared."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name. Must match 00-shared; used to find shared resources and docker-node1."
  type        = string
  default     = "emp"
}

variable "instance_type" {
  description = "EC2 size for the ansible server."
  type        = string
  default     = "t2.micro"
}

variable "root_volume_size" {
  description = "Disk size in GB."
  type        = number
  default     = 10
}

variable "admin_cidr" {
  description = "IP range allowed to SSH in, for example 203.0.113.10/32. Null = your current public IP, detected automatically."
  type        = string
  default     = null

  validation {
    condition     = var.admin_cidr == null || can(cidrhost(var.admin_cidr, 0))
    error_message = "admin_cidr must be a valid CIDR block, for example 203.0.113.10/32."
  }
}

variable "timezone" {
  description = "Server timezone."
  type        = string
  default     = "Asia/Kolkata"
}

variable "deploy_user" {
  description = "User that runs Ansible here and logs in to docker-node1 (itadmin in the project guide). Must match 02-docker-server."
  type        = string
  default     = "itadmin"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,30}$", var.deploy_user))
    error_message = "deploy_user must be a valid Linux user name (lowercase letters, numbers, _ and -)."
  }
}

variable "docker_server_name" {
  description = "Name tag of the server Ansible deploys to (created by 02-docker-server)."
  type        = string
  default     = "docker-node1"
}

variable "project_dir" {
  description = "Ansible project folder with inventory and ansible.cfg (/opt/project in the project guide)."
  type        = string
  default     = "/opt/project"

  validation {
    condition     = can(regex("^/[A-Za-z0-9/_-]+$", var.project_dir))
    error_message = "project_dir must be an absolute path with letters, numbers, /, _ and - only."
  }
}

variable "staging_dir" {
  description = "Folder where Jenkins uploads the app package before Ansible deploys it (/opt/docker in the project guide)."
  type        = string
  default     = "/opt/docker"

  validation {
    condition     = can(regex("^/[A-Za-z0-9/_-]+$", var.staging_dir))
    error_message = "staging_dir must be an absolute path with letters, numbers, /, _ and - only."
  }
}
