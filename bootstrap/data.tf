data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_s3_bucket" "state" {
	bucket = local.state_bucket
}