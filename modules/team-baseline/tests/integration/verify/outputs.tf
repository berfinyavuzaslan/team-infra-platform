output "public_status" {
  value = data.http.public.status_code
}

output "private_status" {
  value = data.http.private.status_code
}