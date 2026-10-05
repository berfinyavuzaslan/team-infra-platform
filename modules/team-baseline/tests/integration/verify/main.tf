resource "aws_s3_object" "probe" {
  for_each = toset([var.public_bucket, var.private_bucket])

  bucket  = each.value
  key     = "probe.txt"
  content = "probe"
}

