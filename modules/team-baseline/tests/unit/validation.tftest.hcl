# Negative tests: every guardrail must reject bad input at plan time.
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
  buckets     = { invoices = { visibility = "private", retention_days = 365 } }
}

run "visibility_must_be_public_or_private" {
  command = plan
  variables {
    buckets = { invoices = { visibility = "internal", retention_days = 365 } }
  }
  expect_failures = [var.buckets]
}

run "at_least_one_bucket_required" {
  command = plan
  variables {
    buckets = {}
  }
  expect_failures = [var.buckets]
}

run "bucket_key_must_be_dns_safe" {
  command = plan
  variables {
    buckets = { Invoices_2024 = { visibility = "private", retention_days = 365 } }
  }
  expect_failures = [var.buckets]
}

run "retention_days_must_be_positive_whole_days" {
  command = plan
  variables {
    buckets = { invoices = { visibility = "private", retention_days = 0.5 } }
  }
  expect_failures = [var.buckets]
}

run "retention_days_cannot_exceed_one_hundred_years" {
  command = plan
  variables {
    buckets = { invoices = { visibility = "private", retention_days = 36501 } }
  }
  expect_failures = [var.buckets]
}

run "team_name_must_not_contain_hyphens" {
  command = plan
  variables {
    team_name = "pay-eu"
  }
  expect_failures = [var.team_name]
}

run "bucket_name_length_enforced" {
  command = plan
  variables {
    name_prefix = "acmeplatform"
    team_name   = "averyverylongteamname123"
    buckets     = { a-very-long-bucket-key-name-here = { visibility = "private", retention_days = 365 } }
  }
  expect_failures = [aws_s3_bucket.this]
}
