output "suffix" {
  value = random_string.suffix.result
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "caller_role_arn" {
  value = data.aws_iam_session_context.current.issuer_arn
}