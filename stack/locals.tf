locals {
  team_file = coalesce(var.team_file, "${path.root}/../teams/${var.team_name}/team.yaml")
  team      = yamldecode(file(local.team_file))
}