data "aws_caller_identity" "current" {}

# Ingest bucket: audio uploads land here, and every stage writes its output here
# (transcripts/, summaries/, action-items/). Account id in the name keeps it
# globally unique.
resource "aws_s3_bucket" "ingest" {
  bucket        = "${local.name}-ingest-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # POC: allow destroy with objects present
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "ingest" {
  bucket                  = aws_s3_bucket.ingest.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "ingest_bucket" {
  description = "S3 bucket for audio uploads and pipeline outputs."
  value       = aws_s3_bucket.ingest.bucket
}
