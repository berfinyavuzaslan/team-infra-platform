# Unit tests: plan-only against a mocked AWS provider. No credentials or network needed.
# Run: terraform test -test-directory=tests/unit

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  team_name   = "payments"
  name_prefix = "acme"
  owner_email = "payments@acme.example"
  cost_center = "CC-1001"
  buckets = {
    invoices      = { visibility = "private", retention_days = 365 }
    public-assets = { visibility = "public" }
  }
}

run "bucket_names_follow_convention" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this["invoices"].bucket == "acme-payments-invoices"
    error_message = "Bucket name must be <prefix>-<team>-<key>."
  }
  assert {
    condition     = aws_s3_bucket.this["public-assets"].bucket == "acme-payments-public-assets"
    error_message = "Bucket name must be <prefix>-<team>-<key>."
  }
  assert {
    condition     = aws_iam_role.this.name == "acme-team-payments" && aws_iam_role.this.path == "/teams/"
    error_message = "Role must be named <prefix>-team-<team> under /teams/."
  }
}

run "private_bucket_blocks_all_public_access" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this["invoices"].block_public_acls,
      aws_s3_bucket_public_access_block.this["invoices"].ignore_public_acls,
      aws_s3_bucket_public_access_block.this["invoices"].block_public_policy,
      aws_s3_bucket_public_access_block.this["invoices"].restrict_public_buckets,
    ])
    error_message = "Private buckets must enable all four public access block settings."
  }
  assert {
    condition     = length([for s in jsondecode(aws_s3_bucket_policy.this["invoices"].policy).Statement : s if s.Effect == "Allow"]) == 0
    error_message = "Private bucket policy must not contain any Allow statement."
  }
}

run "public_bucket_is_read_only_and_acls_stay_blocked" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket_public_access_block.this["public-assets"].block_public_acls &&
      aws_s3_bucket_public_access_block.this["public-assets"].ignore_public_acls &&
      !aws_s3_bucket_public_access_block.this["public-assets"].block_public_policy &&
      !aws_s3_bucket_public_access_block.this["public-assets"].restrict_public_buckets
    )
    error_message = "Public buckets may only relax policy-based blocking; ACLs must remain blocked."
  }
  assert {
    condition = [
      for s in jsondecode(aws_s3_bucket_policy.this["public-assets"].policy).Statement : s.Action if s.Effect == "Allow"
    ] == ["s3:GetObject"]
    error_message = "Public access must be limited to a single s3:GetObject grant (no list, no write)."
  }
}

run "all_buckets_have_baseline_controls" {
  command = plan

  assert {
    condition     = alltrue([for k, v in aws_s3_bucket_ownership_controls.this : one(v.rule).object_ownership == "BucketOwnerEnforced"])
    error_message = "ACLs must be disabled (BucketOwnerEnforced) on every bucket."
  }
  assert {
    condition     = alltrue([for k, v in aws_s3_bucket_versioning.this : one(v.versioning_configuration).status == "Enabled"])
    error_message = "Versioning must be enabled on every bucket."
  }
  assert {
    condition = alltrue([
      for k, v in aws_s3_bucket_object_lock_configuration.this : v.object_lock_enabled == "Enabled" && one(one(v.rule).default_retention).mode == "COMPLIANCE" && one(one(v.rule).default_retention).days == var.buckets[k].retention_days
    ])
    error_message = "Each bucket must enforce its declared default retention in Object Lock Compliance mode."
  }
  assert {
    condition     = one(one(aws_s3_bucket_object_lock_configuration.this["public-assets"].rule).default_retention).days == 90
    error_message = "A bucket without retention_days must default to 90 days."
  }
  assert {
    condition     = alltrue([for k, v in aws_s3_bucket_server_side_encryption_configuration.this : one(one(v.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"])
    error_message = "Default encryption must be enabled on every bucket."
  }
  assert {
    condition = alltrue([
      for k, v in aws_s3_bucket_policy.this : contains([for s in jsondecode(v.policy).Statement : s.Sid], "DenyInsecureTransport")
    ])
    error_message = "Every bucket policy must deny non-TLS requests."
  }
  assert {
    condition     = alltrue([for k, v in aws_s3_bucket.this : v.force_destroy == false])
    error_message = "force_destroy must default to false to protect data."
  }
}

run "role_policy_is_scoped_to_own_buckets" {
  command = plan

  assert {
    condition = toset(flatten([for s in jsondecode(aws_iam_role_policy.s3_access.policy).Statement : s.Resource])) == toset([
      "arn:aws:s3:::acme-payments-invoices",
      "arn:aws:s3:::acme-payments-public-assets",
      "arn:aws:s3:::acme-payments-invoices/*",
      "arn:aws:s3:::acme-payments-public-assets/*",
    ])
    error_message = "Role policy must reference exactly the team's own buckets, with no wildcards."
  }
  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.s3_access.policy).Statement : s.Condition.StringEquals["s3:ResourceAccount"] == "111122223333"
    ])
    error_message = "Every statement must be pinned to the deployment account via s3:ResourceAccount."
  }
}

run "role_policy_excludes_admin_and_destructive_actions" {
  command = plan

  assert {
    condition = length(setintersection(
      toset(flatten([for s in jsondecode(aws_iam_role_policy.s3_access.policy).Statement : s.Action])),
      toset(["s3:*", "s3:DeleteBucket", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:PutBucketPublicAccessBlock", "s3:PutBucketAcl", "s3:PutObjectAcl", "s3:DeleteObjectVersion", "s3:PutBucketVersioning", "s3:PutObjectRetention"])
    )) == 0
    error_message = "Team role must not be able to change bucket configuration or purge object versions."
  }
}

run "trust_policy_is_limited_to_deployment_account" {
  command = plan

  assert {
    condition = (
      one(jsondecode(aws_iam_role.this.assume_role_policy).Statement).Principal.AWS == "arn:aws:iam::111122223333:root" &&
      one(jsondecode(aws_iam_role.this.assume_role_policy).Statement).Condition.StringEquals["aws:PrincipalAccount"] == "111122223333"
    )
    error_message = "The role trust policy must only delegate to identities in the deployment account."
  }
}

run "ownership_tags_are_enforced" {
  command = plan

  variables {
    tags = { Team = "someone-else", Project = "checkout" }
  }

  assert {
    condition     = aws_s3_bucket.this["invoices"].tags["Team"] == "payments"
    error_message = "Callers must not be able to override the Team tag."
  }
  assert {
    condition     = aws_s3_bucket.this["invoices"].tags["CostCenter"] == "CC-1001" && aws_s3_bucket.this["invoices"].tags["Owner"] == "payments@acme.example"
    error_message = "Cost allocation tags must be applied."
  }
  assert {
    condition     = aws_s3_bucket.this["public-assets"].tags["Visibility"] == "public"
    error_message = "Buckets must carry a Visibility tag for auditing."
  }
  assert {
    condition     = aws_s3_bucket.this["invoices"].tags["Project"] == "checkout"
    error_message = "Additional tags must be preserved."
  }
  assert {
    condition     = aws_iam_role.this.tags["Team"] == "payments"
    error_message = "Role must be tagged with the owning team."
  }
}

run "outputs_contract" {
  command = plan

  assert {
    condition = output.buckets == {
      invoices      = { name = "acme-payments-invoices", arn = "arn:aws:s3:::acme-payments-invoices", visibility = "private" }
      public-assets = { name = "acme-payments-public-assets", arn = "arn:aws:s3:::acme-payments-public-assets", visibility = "public" }
    }
    error_message = "buckets output shape is a contract consumed by the stack and downstream tooling."
  }
}
