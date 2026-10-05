variable "team_name" {
  description = "Unique team identifier. Used in resource names and the Team tag."
  type        = string

  # No hyphens: guarantees <prefix>-<team>-<bucket> is unambiguous, so team "pay" with
  # bucket "eu-data" can never collide with team "pay-eu" with bucket "data".
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,23}$", var.team_name))
    error_message = "team_name must be 3-24 lowercase letters or digits, starting with a letter (no hyphens)."
  }
}

variable "name_prefix" {
  description = "Organisation prefix for every resource name. Buckets are named <name_prefix>-<team_name>-<bucket_key>."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,11}$", var.name_prefix))
    error_message = "name_prefix must be 2-12 lowercase alphanumerics starting with a letter (no hyphens, so team names cannot be confused with the prefix)."
  }
}

variable "owner_email" {
  description = "Distribution list of the owning team. Applied as the Owner tag."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.owner_email))
    error_message = "owner_email must be a valid e-mail address."
  }
}

variable "cost_center" {
  description = "Cost centre the team's spend is charged to. Applied as the CostCenter tag."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]{2,32}$", var.cost_center))
    error_message = "cost_center must be 2-32 alphanumerics or hyphens."
  }
}

variable "buckets" {
  description = <<-EOT
    Buckets to create, keyed by short name. The key becomes part of the bucket name.
    Each bucket MUST declare visibility = "public" | "private". retention_days is
    optional and defaults to 90 days for Object Lock Compliance retention.
  EOT
  type = map(object({
    visibility     = string
    retention_days = optional(number, 90)
  }))

  validation {
    condition     = length(var.buckets) >= 1 && length(var.buckets) <= 50
    error_message = "A team must declare between 1 and 50 buckets."
  }

  validation {
    condition     = alltrue([for k in keys(var.buckets) : can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", k))])
    error_message = "Bucket keys must be 3-32 chars of lowercase letters, digits and hyphens, and must not start or end with a hyphen."
  }

  validation {
    condition     = alltrue([for b in values(var.buckets) : contains(["public", "private"], b.visibility)])
    error_message = "visibility must be exactly \"public\" or \"private\"."
  }

  validation {
    condition     = alltrue([for b in values(var.buckets) : b.retention_days >= 1 && b.retention_days <= 36500 && b.retention_days == floor(b.retention_days)])
    error_message = "retention_days must be a whole number between 1 and 36500 days."
  }
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary attached to the team role. Set by the platform, never by teams."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags. Ownership tags (Team, Owner, CostCenter, ManagedBy) always take precedence."
  type        = map(string)
  default     = {}
}

variable "force_destroy" {
  description = "Allow destroying non-empty buckets. For ephemeral test environments only; also disables Object Lock configuration so tests can clean up. The platform stack never exposes this."
  type        = bool
  default     = false
}
