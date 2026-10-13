terraform {
  required_version = ">= 1.11"
  backend "s3" {}
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { ManagedBy = "terraform", Team = "platform", Component = "team-infra-bootstrap" }
  }
}