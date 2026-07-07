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

# The web app (infra/terraform/web) uploads and downloads directly against this
# bucket from the browser using presigned URLs — CORS just permits the
# cross-origin call; the presigned URL itself is the access control. The
# allowed origin can't be pinned to the CloudFront domain without coupling the
# two stacks, so it stays "*".
resource "aws_s3_bucket_cors_configuration" "ingest" {
  bucket = aws_s3_bucket.ingest.id

  cors_rule {
    allowed_methods = ["GET", "PUT", "HEAD"]
    allowed_origins = ["*"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

output "ingest_bucket" {
  description = "S3 bucket for audio uploads and pipeline outputs."
  value       = aws_s3_bucket.ingest.bucket
}
