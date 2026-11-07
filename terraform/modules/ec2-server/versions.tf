# Terraform and provider versions this module works with.
# A module only sets minimum versions; each server folder pins the exact provider.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
  }
}
