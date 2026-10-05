variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "name_prefix" {
  type    = string
  default = "acme"
}

variable "github_repository" {
  description = "GitHub owner/repository connected to CodePipeline."
  type        = string
  default     = "acme/team-infra"
}

variable "codestar_connection_arn" {
  description = "An active CodeStar connection ARN authorized for github_repository."
  type        = string
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