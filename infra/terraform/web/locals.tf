data "aws_caller_identity" "current" {}

locals {
  name = "arp-web"

  # The poc stack's ingest bucket, referenced by its deterministic name rather
  # than remote state: after a nightly `terraform destroy` the poc outputs are
  # gone, but this stack must keep planning cleanly. Must stay in sync with
  # aws_s3_bucket.ingest in ../poc/s3.tf.
  ingest_bucket = "arp-ingest-${data.aws_caller_identity.current.account_id}"

  common_tags = {
    Project   = "audio-recording-processor"
    Env       = "web"
    ManagedBy = "terraform"
  }
}
