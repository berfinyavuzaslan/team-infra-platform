# Integration tests: real apply in a SANDBOX account, then automatic destroy.
# Requires credentials for a sandbox account whose account-level S3 Block Public Access
# permits public bucket policies.
# Run: terraform test -test-directory=tests/integration

variables {
  region = "eu-central-1"
}

provider "aws" {
  region = var.region
}

run "setup" {
  module {
    source = "./tests/integration/setup"
  }
}

run "apply_module" {
  command = apply

  variables {
    team_name   = "it${run.setup.suffix}"
    name_prefix = "sumupit"
    owner_email = "platform@sumup.example"
    cost_center = "CC-PLATFORM"
    # Test-only cleanup mode omits default retention so Terraform can destroy its probe objects.
    force_destroy = true
    buckets = {
      private-data  = { visibility = "private", retention_days = 1 }
      public-assets = { visibility = "public", retention_days = 1 }
    }
  }

  assert {
    condition     = output.buckets["private-data"].name == "sumupit-it${run.setup.suffix}-private-data"
    error_message = "Unexpected bucket name."
  }
  assert {
    condition     = startswith(output.role_arn, "arn:aws:iam::${run.setup.account_id}:role/teams/")
    error_message = "Role not created under /teams/ in the sandbox account."
  }
}

run "anonymous_access_matches_visibility" {
  module {
    source = "./tests/integration/verify"
  }

  variables {
    public_bucket  = run.apply_module.buckets["public-assets"].name
    private_bucket = run.apply_module.buckets["private-data"].name
  }

  assert {
    condition     = output.public_status == 200
    error_message = "Anonymous GET on a public bucket object must succeed."
  }
  assert {
    condition     = output.private_status == 403
    error_message = "Anonymous GET on a private bucket object must be denied."
  }
}
