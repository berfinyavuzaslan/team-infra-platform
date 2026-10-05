# Generic root module: identical for every team. A team is selected purely by
# -var=team_name and its own state key, so onboarding never touches this code.

module "team" {
  source = "../modules/team-baseline"

  team_name   = local.team.team
  name_prefix = var.name_prefix
  owner_email = local.team.owner
  cost_center = local.team.cost_center
  buckets     = local.team.buckets

  # Created by bootstrap/; the CI apply role cannot create team roles without it.
  permissions_boundary_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.name_prefix}-team-boundary"

  tags = {
    Repository = var.repository
    ConfigPath = "teams/${var.team_name}/team.yaml"
  }
}
