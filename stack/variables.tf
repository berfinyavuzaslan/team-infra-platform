variable "team_name" {
  description = "Team to deploy. Must match the directory name under teams/ and the 'team' field in the file."
  type        = string
}

variable "team_file" {
  description = "Override path to the team file. Used by offboarding to destroy from the last deployed revision."
  type        = string
  default     = null
}

variable "aws_region" {
  description = "Region for all team resources."
  type        = string
  default     = "eu-north-1"
}

variable "name_prefix" {
  description = "Organisation prefix for resource names."
  type        = string
  default     = "sumup"
}

variable "repository" {
  description = "Source repository, recorded as a tag for traceability."
  type        = string
  default     = "berfinyavuzaslan/team-infra-platform"
}
