locals {
  bucket_names = { for k, _ in var.buckets : k => "${var.name_prefix}-${var.team_name}-${k}" }

  # ARNs are derived from names (not from resource attributes) so policies are fully
  # known at plan time and can be asserted in unit tests without AWS.
  bucket_arns = { for k, name in local.bucket_names : k => "arn:${data.aws_partition.current.partition}:s3:::${name}" }

  tags = merge(var.tags, {
    Team       = var.team_name
    Owner      = var.owner_email
    CostCenter = var.cost_center
    ManagedBy  = "terraform"
    Module     = "team-baseline"
  })

  bucket_policies = {
    for k, b in var.buckets : k => jsonencode({
      Version = "2012-10-17"
      Statement = concat(
        [{
          Sid       = "DenyInsecureTransport"
          Effect    = "Deny"
          Principal = "*"
          Action    = "s3:*"
          Resource  = [local.bucket_arns[k], "${local.bucket_arns[k]}/*"]
          Condition = { Bool = { "aws:SecureTransport" = "false" } }
        }],
        b.visibility == "public" ? [{
          Sid       = "AllowAnonymousReadOnly"
          Effect    = "Allow"
          Principal = "*"
          Action    = "s3:GetObject"
          Resource  = "${local.bucket_arns[k]}/*"
        }] : []
      )
    })
  }

  # Explicit ARNs (no wildcards) plus s3:ResourceAccount, so the role can never reach a
  # same-named bucket owned by another account if a name is already taken globally.
  same_account = { StringEquals = { "s3:ResourceAccount" = data.aws_caller_identity.current.account_id } }

  role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ListTeamBuckets"
        Effect    = "Allow"
        Action    = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"]
        Resource  = values(local.bucket_arns)
        Condition = local.same_account
      },
      {
        Sid    = "ReadWriteTeamObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
        ]
        Resource  = [for arn in values(local.bucket_arns) : "${arn}/*"]
        Condition = local.same_account
      },
    ]
  })

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "TrustDeploymentAccount"
      Effect    = "Allow"
      Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}
