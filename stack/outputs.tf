output "team_name" {
  description = "Deployed team."
  value       = module.team.team_name

  # Guards against a copied/renamed directory writing into another team's state key.
  precondition {
    condition     = local.team.team == var.team_name
    error_message = "The 'team' field in ${local.team_file} must equal the directory name (${var.team_name})."
  }

}

output "role_arn" {
  description = "Team workload role ARN."
  value       = module.team.role_arn
}

output "buckets" {
  description = "Team buckets keyed by short name."
  value       = module.team.buckets
}
