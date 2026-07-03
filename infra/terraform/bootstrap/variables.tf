variable "region" {
  description = "AWS region for the state bucket. Keep this the same as the main config."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = <<-EOT
    Globally-unique S3 bucket name for Terraform remote state.
    S3 bucket names are global across all AWS accounts, so if apply fails with
    BucketAlreadyExists, pick a different suffix.
  EOT
  type        = string
  default     = "audio-recording-processor-tfstate-awittig"
}
