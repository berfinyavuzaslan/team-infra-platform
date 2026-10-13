# Contract tests: the stack correctly maps a team file onto the module.
# Run (from stack/): terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

run "team_file_is_mapped_to_module" {
  command = plan

  variables {
    team_name = "fixture"
    team_file = "tests/fixtures/valid.yaml"
  }

  assert {
    condition     = output.team_name == "fixture"
    error_message = "Team name not propagated."
  }
  assert {
    condition = output.buckets == {
      reports = { name = "sumup-fixture-reports", arn = "arn:aws:s3:::sumup-fixture-reports", visibility = "private" }
      website = { name = "sumup-fixture-website", arn = "arn:aws:s3:::sumup-fixture-website", visibility = "public" }
    }
    error_message = "Buckets not mapped from the team file."
  }
  assert {
    condition     = module.team.role_name == "sumup-team-fixture"
    error_message = "Role not created for the team."
  }
}

run "directory_and_team_field_must_match" {
  command = plan

  variables {
    team_name = "othername"
    team_file = "tests/fixtures/valid.yaml"
  }

  expect_failures = [output.team_name]
}
