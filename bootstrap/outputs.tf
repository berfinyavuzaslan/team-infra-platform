output "state_bucket" {
  value = data.aws_s3_bucket.state.id
}

output "plan_role_arn" {
  value = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  value = aws_iam_role.apply.arn
}

output "team_permissions_boundary_arn" {
  value = aws_iam_policy.team_boundary.arn
}

output "plan_pipeline_name" {
  value = aws_codepipeline.plan.name
}

output "apply_pipeline_name" {
  value = aws_codepipeline.apply.name
}