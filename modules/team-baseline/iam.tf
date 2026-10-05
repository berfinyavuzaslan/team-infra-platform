resource "aws_iam_role" "this" {
  name                 = "${var.name_prefix}-team-${var.team_name}"
  path                 = "/teams/"
  description          = "Workload role for team ${var.team_name}. Managed by the platform team-baseline module."
  assume_role_policy   = local.assume_role_policy
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600

  tags = local.tags
}

resource "aws_iam_role_policy" "s3_access" {
  name   = "team-buckets-access"
  role   = aws_iam_role.this.id
  policy = local.role_policy
}
