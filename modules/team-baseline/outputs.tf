output "team_name" {
  description = "Team identifier."
  value       = var.team_name
}

output "role_arn" {
  description = "ARN of the team workload role."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the team workload role."
  value       = aws_iam_role.this.name
}

output "buckets" {
  description = "Created buckets keyed by short name."
  value = {
    for k, b in var.buckets : k => {
      name       = local.bucket_names[k]
      arn        = local.bucket_arns[k]
      visibility = b.visibility
    }
  }
}
