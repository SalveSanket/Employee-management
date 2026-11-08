# =============================================================================
# 00-shared: inputs (all have safe defaults; override in terraform.tfvars)
# =============================================================================

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "ap-south-1" # Mumbai
}

variable "project" {
  description = "Project name. Prefix for resource names; other folders find shared resources by it."
  type        = string
  default     = "emp"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project))
    error_message = "project may contain only lowercase letters, numbers and hyphens."
  }
}

variable "vpc_cidr" {
  description = "IP range of the VPC (private network)."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block, for example 10.0.0.0/16."
  }
}

variable "public_subnet_cidr" {
  description = "IP range of the public subnet. Must be inside vpc_cidr."
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "public_subnet_cidr must be a valid CIDR block, for example 10.0.1.0/24."
  }
}

variable "availability_zone" {
  description = "Availability zone for the subnet. Null = the first available zone in the region."
  type        = string
  default     = null
}

variable "login_key_path" {
  description = "Where the SSH login private key is saved on your machine."
  type        = string
  default     = "~/.ssh/emp-project.pem"
}
