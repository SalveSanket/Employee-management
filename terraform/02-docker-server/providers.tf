# =============================================================================
# 02-docker-server: Terraform settings and providers
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Creates the AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Detects your current public IP for the SSH firewall rule
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
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
      Stack     = "02-docker-server"
    }
  }
}
