# =============================================================================
# 04-jenkins-server: inputs (all have safe defaults; override in terraform.tfvars)
# =============================================================================

variable "aws_region" {
  description = "AWS region. Must match 00-shared."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name. Must match 00-shared; used to find shared resources and the ansible server."
  type        = string
  default     = "emp"
}

variable "instance_type" {
  description = "EC2 size. Jenkins needs at least 2 GB of memory, so t3.small is the minimum."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "Disk size in GB (Jenkins home, workspaces, npm cache)."
  type        = number
  default     = 20
}

variable "admin_cidr" {
  description = "IP range allowed to SSH in and open the Jenkins UI. Null = your current public IP, detected automatically."
  type        = string
  default     = null

  validation {
    condition     = var.admin_cidr == null || can(cidrhost(var.admin_cidr, 0))
    error_message = "admin_cidr must be a valid CIDR block, for example 203.0.113.10/32."
  }
}

variable "allow_github_webhooks" {
  description = "Allow GitHub's official webhook IP ranges to reach Jenkins on port 8080 (push -> automatic build)."
  type        = bool
  default     = true
}

variable "jenkins_port" {
  description = "Port of the Jenkins web UI (Jenkins package default)."
  type        = number
  default     = 8080
}

variable "timezone" {
  description = "Server timezone."
  type        = string
  default     = "Asia/Kolkata"
}

variable "java_major_version" {
  description = "Java (Amazon Corretto) major version. Current Jenkins LTS releases require Java 21."
  type        = number
  default     = 21

  validation {
    condition     = contains([21, 25], var.java_major_version)
    error_message = "java_major_version must be 21 or 25 (Java versions supported by current Jenkins)."
  }
}

variable "node_major_version" {
  description = "Node.js major version, used by the pipeline to build the app (npm ci, npm run build)."
  type        = number
  default     = 22

  validation {
    condition     = contains([20, 22, 24], var.node_major_version)
    error_message = "node_major_version must be 20, 22 or 24 (versions available on Amazon Linux 2023)."
  }
}

variable "ansible_server_name" {
  description = "Name tag of the ansible server (created by 03-ansible-server). Jenkins gets SSH access to it."
  type        = string
  default     = "ansible"
}
