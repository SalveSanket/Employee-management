# =============================================================================
# 01-dev-server: inputs (all have safe defaults; override in terraform.tfvars)
# =============================================================================

variable "aws_region" {
  description = "AWS region. Must match 00-shared."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name. Must match 00-shared; used to find the shared VPC, subnet and key."
  type        = string
  default     = "emp"
}

variable "instance_type" {
  description = "EC2 size for dev1."
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

variable "node_major_version" {
  description = "Node.js major version installed from the Amazon Linux 2023 repository."
  type        = number
  default     = 22

  validation {
    condition     = contains([20, 22, 24], var.node_major_version)
    error_message = "node_major_version must be 20, 22 or 24 (versions available on Amazon Linux 2023)."
  }
}

variable "repo_url" {
  description = "Git repository cloned into /devpro1 on first boot. Empty = do not clone."
  type        = string
  default     = "https://github.com/SalveSanket/Employee-management.git"

  validation {
    condition     = var.repo_url == "" || can(regex("^https://[A-Za-z0-9./_-]+\\.git$", var.repo_url))
    error_message = "repo_url must be an https Git URL ending in .git, or empty."
  }
}

variable "git_user_name" {
  description = "Git commit author name for ec2-user. Empty = not set."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[A-Za-z0-9 ._-]*$", var.git_user_name))
    error_message = "git_user_name may contain only letters, numbers, spaces, dots, underscores and hyphens."
  }
}

variable "git_user_email" {
  description = "Git commit author email for ec2-user. Empty = not set."
  type        = string
  default     = ""

  validation {
    condition     = var.git_user_email == "" || can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", var.git_user_email))
    error_message = "git_user_email must be a valid email address, or empty."
  }
}
