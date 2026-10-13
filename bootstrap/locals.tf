locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  # Deliberately does NOT match the "<prefix>-*" pattern granted to CI for team buckets.
  state_bucket     = var.state_bucket_name
  state_bucket_arn = "arn:${local.partition}:s3:::${local.state_bucket}"
  team_buckets_arn = "arn:${local.partition}:s3:::${var.name_prefix}-*"
  team_roles_arn   = "arn:${local.partition}:iam::${local.account_id}:role/teams/*"
  boundary_arn     = "arn:${local.partition}:iam::${local.account_id}:policy/${var.name_prefix}-team-boundary"

  artifact_bucket = "ci-${var.name_prefix}-team-infra-${local.account_id}"
  pipeline_paths  = ["teams/**", "modules/**", "stack/**", "scripts/**", "schema/**", "buildspec/**"]

  read_statements = [
    {
      Sid      = "ReadTeamBucketConfig"
      Effect   = "Allow"
      Action   = ["s3:Get*", "s3:List*"]
      Resource = local.team_buckets_arn # bucket-level only: no object reads
    },
    {
      Sid      = "ReadTeamRoles"
      Effect   = "Allow"
      Action   = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies"]
      Resource = local.team_roles_arn
    },
    {
      Sid      = "ReadState"
      Effect   = "Allow"
      Action   = ["s3:ListBucket"]
      Resource = local.state_bucket_arn
    },
    {
      Sid      = "ReadStateObjects"
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${local.state_bucket_arn}/teams/*"
    },
    {
      Sid      = "StateLocking"
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Resource = "${local.state_bucket_arn}/teams/*.tflock"
    },
    {
      Sid      = "UseStateBucketKmsKey"
      Effect   = "Allow"
      Action   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"]
      Resource = "*"
      Condition = {
        StringEquals = {
          "kms:ViaService"                   = "s3.${var.aws_region}.amazonaws.com"
          "kms:EncryptionContext:aws:s3:arn" = local.state_bucket_arn
        }
      }
    },
  ]

  codebuild_trust = {
    for name in ["plan", "apply"] : name => jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Service = "codebuild.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:codebuild:${var.aws_region}:${local.account_id}:project/${var.name_prefix}-team-infra-*" }
        }
      }]
    })
  }

  codebuild_log_arn = "arn:${local.partition}:logs:${var.aws_region}:${local.account_id}:log-group:/aws/codebuild/${var.name_prefix}-team-infra-*:*"
}