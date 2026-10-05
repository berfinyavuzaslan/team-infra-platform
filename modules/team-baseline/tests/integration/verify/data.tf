# Unauthenticated requests: exactly what an anonymous internet user would see.
data "http" "public" {
  url        = "https://${var.public_bucket}.s3.${var.region}.amazonaws.com/probe.txt"
  depends_on = [aws_s3_object.probe]
}

data "http" "private" {
  url        = "https://${var.private_bucket}.s3.${var.region}.amazonaws.com/probe.txt"
  depends_on = [aws_s3_object.probe]
}