variable "aws_region" {
  type    = string
  default = "eu-north-1"
}

variable "state_bucket_name" {
  description = "S3 bucket used for team and bootstrap Terraform state."
  type        = string
  default     = "sumup-team-infrastructure-assessment"
}

variable "name_prefix" {
  type    = string
  default = "sumup"
}

variable "github_repository" {
  description = "GitHub owner/repository connected to CodePipeline."
  type        = string
  default     = "berfinyavuzaslan/team-infra-platform"
}

variable "team_parallelism" {
  description = "Maximum number of team Terraform jobs to run concurrently in CodeBuild."
  type        = number
  default     = 8

  validation {
    condition     = var.team_parallelism >= 1 && var.team_parallelism <= 20 && var.team_parallelism == floor(var.team_parallelism)
    error_message = "team_parallelism must be a whole number between 1 and 20."
  }
}