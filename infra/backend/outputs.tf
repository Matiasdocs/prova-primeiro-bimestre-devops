output "bucket_name" {
  value = local.bucket_name
}

output "dynamodb_table" {
  value = aws_dynamodb_table.locks.name
}