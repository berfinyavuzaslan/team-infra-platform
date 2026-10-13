resource "aws_s3_bucket" "artifacts" {
  bucket = local.artifact_bucket

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_codestarconnections_connection" "github" {
  name          = "${var.name_prefix}-team-infra-github"
  provider_type = "GitHub"
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_ssm_parameter" "last_applied_revision" {
  name        = "/${var.name_prefix}/team-infra/last-applied-revision"
  description = "Last successfully applied Git revision used to detect changes between pipeline runs."
  type        = "String"
  value       = "UNINITIALIZED"
}

resource "aws_iam_role" "pipeline" {
  name = "${var.name_prefix}-team-infra-pipeline"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "pipeline" {
  role = aws_iam_role.pipeline.id
  name = "pipeline"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "UseGitHubConnection"
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
        Resource = aws_codestarconnections_connection.github.arn
      },
      {
        Sid      = "RunBuildProjects"
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
        Resource = "arn:${local.partition}:codebuild:${var.aws_region}:${local.account_id}:project/${var.name_prefix}-team-infra-*"
      },
      {
        Sid      = "ManagePipelineArtifacts"
        Effect   = "Allow"
        Action   = ["s3:GetBucketVersioning", "s3:GetBucketAcl", "s3:GetBucketLocation", "s3:ListBucket"]
        Resource = aws_s3_bucket.artifacts.arn
      },
      {
        Sid      = "ReadWritePipelineArtifacts"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:PutObjectAcl", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },
    ]
  })
}

resource "aws_codebuild_project" "quality" {
  name          = "${var.name_prefix}-team-infra-quality"
  description   = "Static, schema, and Terraform unit/contract checks."
  service_role  = aws_iam_role.plan.arn
  build_timeout = 60

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_MEDIUM"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    environment_variable {
      name  = "TF_VERSION"
      value = "1.11.4"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec/quality.yml"
  }
}

resource "aws_codebuild_project" "plan" {
  name          = "${var.name_prefix}-team-infra-plan"
  description   = "Read-only per-team Terraform plans for pull requests."
  service_role  = aws_iam_role.plan.arn
  build_timeout = 360

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_MEDIUM"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    environment_variable {
      name  = "TF_VERSION"
      value = "1.11.4"
    }
    environment_variable {
      name  = "MODE"
      value = "plan"
    }
    environment_variable {
      name  = "TEAM_PARALLELISM"
      value = tostring(var.team_parallelism)
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec/team-infra.yml"
  }
}

resource "aws_codebuild_project" "apply" {
  name          = "${var.name_prefix}-team-infra-apply"
  description   = "Apply approved main-branch changes and verify idempotency."
  service_role  = aws_iam_role.apply.arn
  build_timeout = 720

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_MEDIUM"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    environment_variable {
      name  = "TF_VERSION"
      value = "1.11.4"
    }
    environment_variable {
      name  = "MODE"
      value = "apply"
    }
    environment_variable {
      name  = "TEAM_PARALLELISM"
      value = tostring(var.team_parallelism)
    }
    environment_variable {
      name  = "CHECKPOINT_PARAMETER"
      value = aws_ssm_parameter.last_applied_revision.name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec/team-infra.yml"
  }
}

resource "aws_codepipeline" "plan" {
  name           = "${var.name_prefix}-team-infra-plan"
  role_arn       = aws_iam_role.pipeline.arn
  pipeline_type  = "V2"
  execution_mode = "SUPERSEDED"

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceOutput"]
      configuration = {
        ConnectionArn        = aws_codestarconnections_connection.github.arn
        FullRepositoryId     = var.github_repository
        BranchName           = "main"
        DetectChanges        = "false"
        OutputArtifactFormat = "CODEBUILD_CLONE_REF"
      }
    }
  }

  stage {
    name = "Quality"
    action {
      name            = "QualityChecks"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceOutput"]
      configuration   = { ProjectName = aws_codebuild_project.quality.name }
    }
  }

  stage {
    name = "Plan"
    action {
      name            = "TeamPlans"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceOutput"]
      configuration   = { ProjectName = aws_codebuild_project.plan.name }
    }
  }

  trigger {
    provider_type = "CodeStarSourceConnection"
    git_configuration {
      source_action_name = "Source"
      pull_request {
        events = ["OPEN", "UPDATED"]
        branches {
          includes = ["main"]
        }
      }
    }
  }
}

resource "aws_codepipeline" "apply" {
  name           = "${var.name_prefix}-team-infra-apply"
  role_arn       = aws_iam_role.pipeline.arn
  pipeline_type  = "V2"
  execution_mode = "QUEUED"

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceOutput"]
      configuration = {
        ConnectionArn        = aws_codestarconnections_connection.github.arn
        FullRepositoryId     = var.github_repository
        BranchName           = "main"
        DetectChanges        = "false"
        OutputArtifactFormat = "CODEBUILD_CLONE_REF"
      }
    }
  }

  stage {
    name = "Quality"
    action {
      name            = "QualityChecks"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceOutput"]
      configuration   = { ProjectName = aws_codebuild_project.quality.name }
    }
  }

  stage {
    name = "PlatformApproval"
    action {
      name     = "ApproveDeployment"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"
      configuration = {
        CustomData = "Review the CodeBuild plans for this revision. Public bucket changes and offboarding require explicit security/platform review."
      }
    }
  }

  stage {
    name = "Apply"
    action {
      name            = "ApplyTeamChanges"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceOutput"]
      configuration   = { ProjectName = aws_codebuild_project.apply.name }
    }
  }

  trigger {
    provider_type = "CodeStarSourceConnection"
    git_configuration {
      source_action_name = "Source"
      push {
        branches {
          includes = ["main"]
        }
        file_paths {
          includes = local.pipeline_paths
        }
      }
    }
  }
}