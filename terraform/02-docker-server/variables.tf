# =============================================================================
# 02-docker-server: inputs (all have safe defaults; override in terraform.tfvars)
# =============================================================================

variable "aws_region" {
  description = "AWS region. Must match 00-shared."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name. Must match 00-shared; used to find the shared VPC, subnet, key and SSM parameters."
  type        = string
  default     = "emp"
}

variable "instance_type" {
  description = "EC2 size for docker-node1."
  type        = string
  default     = "t2.micro"
}

variable "root_volume_size" {
  description = "Disk size in GB. Docker images need space, so 15 GB is the default."
  type        = number
  default     = 15
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

variable "web_cidr" {
  description = "IP range allowed to open the website on port 80. 0.0.0.0/0 = everyone."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.web_cidr, 0))
    error_message = "web_cidr must be a valid CIDR block."
  }
}

variable "timezone" {
  description = "Server timezone."
  type        = string
  default     = "Asia/Kolkata"
}

variable "deploy_user" {
  description = "User that Ansible logs in as (itadmin in the project guide)."
  type        = string
  default     = "itadmin"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,30}$", var.deploy_user))
    error_message = "deploy_user must be a valid Linux user name (lowercase letters, numbers, _ and -)."
  }
}

variable "app_dir" {
  description = "Folder where Ansible places the application files (/opt/docker in the project guide)."
  type        = string
  default     = "/opt/docker"

  validation {
    condition     = can(regex("^/[A-Za-z0-9/_-]+$", var.app_dir))
    error_message = "app_dir must be an absolute path with letters, numbers, /, _ and - only."
  }
}
