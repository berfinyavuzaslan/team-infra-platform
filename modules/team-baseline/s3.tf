resource "aws_s3_bucket" "this" {
  for_each = var.buckets

  bucket        = local.bucket_names[each.key]
  force_destroy = var.force_destroy

  tags = merge(local.tags, {
    Visibility = each.value.visibility
  })

  lifecycle {
    precondition {
      condition     = length(local.bucket_names[each.key]) <= 63
      error_message = "Bucket name \"${local.bucket_names[each.key]}\" exceeds the S3 limit of 63 characters. Use a shorter bucket key."
    }
  }
}

# Disables ACLs entirely: access is governed only by IAM and bucket policies.
resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Public buckets only relax the *policy* settings; public ACLs stay blocked.
resource "aws_s3_bucket_public_access_block" "this" {
  for_each = var.buckets

  bucket                  = aws_s3_bucket.this[each.key].id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = each.value.visibility == "private"
  restrict_public_buckets = each.value.visibility == "private"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "this" {
  for_each = var.force_destroy ? {} : var.buckets

  bucket              = aws_s3_bucket.this[each.key].id
  object_lock_enabled = "Enabled"

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = each.value.retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id
  policy = local.bucket_policies[each.key]

  # A public policy is rejected while BlockPublicPolicy is still true.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
