output "state_bucket_name" {
  description = "Name of the S3 bucket holding remote state. Put this in ../poc/backend.tf."
  value       = aws_s3_bucket.state.bucket
}

output "region" {
  description = "Region of the state bucket."
  value       = var.region
}
