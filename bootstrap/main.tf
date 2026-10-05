# One-time platform bootstrap (applied by platform admins, own local/remote state).
# Creates: state and artifact buckets, CodePipeline/CodeBuild roles, and team permissions boundary.

# --- State bucket ----------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Versioning = point-in-time recovery of any team's state, and audit trail after offboarding.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [local.state_bucket_arn, "${local.state_bucket_arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

# --- Permissions boundary for every team role --------------------------------------
# Even if a team role's inline policy were widened, it could never exceed object-level
# access to team buckets.

resource "aws_iam_policy" "team_boundary" {
  name        = "${var.name_prefix}-team-boundary"
  description = "Maximum permissions any team role can ever have."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TeamBucketDataAccess"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads", "s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
        Resource = [local.team_buckets_arn, "${local.team_buckets_arn}/*"]
      },
      {
        Sid      = "NeverTouchState"
        Effect   = "Deny"
        Action   = "s3:*"
        Resource = [local.state_bucket_arn, "${local.state_bucket_arn}/*"]
      },
    ]
  })
}

# --- CodeBuild roles ---------------------------------------------------------------

# PR plans are read-only apart from their state lockfiles and CodeBuild artifacts/logs.
resource "aws_iam_role" "plan" {
  name               = "${var.name_prefix}-team-infra-plan"
  assume_role_policy = local.codebuild_trust["plan"]
}

resource "aws_iam_role_policy" "plan" {
  role = aws_iam_role.plan.id
  name = "plan"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(local.read_statements, [
      {
        Sid      = "CodeBuildLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = local.codebuild_log_arn
      },
      {
        Sid      = "CloneConnectedRepository"
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
        Resource = var.codestar_connection_arn
      },
      {
        Sid      = "ReadPipelineArtifacts"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },
    ])
  })
}

# Applies from main only, after a CodePipeline manual approval. Can manage team buckets and team roles,
# but can only create roles that carry the team boundary, and cannot read bucket data.
resource "aws_iam_role" "apply" {
  name               = "${var.name_prefix}-team-infra-apply"
  assume_role_policy = local.codebuild_trust["apply"]
}

resource "aws_iam_role_policy" "apply" {
  role = aws_iam_role.apply.id
  name = "apply"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(local.read_statements, [
      {
        Sid      = "CodeBuildLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = local.codebuild_log_arn
      },
      {
        Sid      = "CloneConnectedRepository"
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
        Resource = var.codestar_connection_arn
      },
      {
        Sid      = "ReadPipelineArtifacts"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },
      {
        Sid      = "UpdateDeploymentCursor"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:PutParameter"]
        Resource = aws_ssm_parameter.last_applied_revision.arn
      },
      {
        Sid      = "ManageTeamBuckets"
        Effect   = "Allow"
        Action   = ["s3:CreateBucket", "s3:DeleteBucket", "s3:Put*", "s3:DeleteBucketPolicy"]
        Resource = local.team_buckets_arn
      },
      {
        Sid      = "WriteState"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${local.state_bucket_arn}/teams/*"
      },
      {
        Sid      = "CreateTeamRolesOnlyWithBoundary"
        Effect   = "Allow"
        Action   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
        Resource = local.team_roles_arn
        Condition = {
          StringEquals = { "iam:PermissionsBoundary" = local.boundary_arn }
        }
      },
      {
        Sid      = "ManageTeamRoles"
        Effect   = "Allow"
        Action   = ["iam:DeleteRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:TagRole", "iam:UntagRole"]
        Resource = local.team_roles_arn
      },
      {
        Sid      = "NeverRemoveBoundary"
        Effect   = "Deny"
        Action   = ["iam:DeleteRolePermissionsBoundary"]
        Resource = "*"
      },
    ])
  })
}

