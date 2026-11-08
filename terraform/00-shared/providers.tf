# =============================================================================
# 00-shared: Terraform settings and providers
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Creates the AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Generates the SSH key pairs
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    # Saves the login private key on your Mac
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Added to every AWS resource created from this folder
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "00-shared"
    }
  }
}
