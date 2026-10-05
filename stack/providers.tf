terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial configuration: shared settings live in backend.hcl, the per-team state key
  # is injected at init time by scripts/tf.sh (teams/<team>/terraform.tfstate).
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}