# Bootstrap: creates the S3 bucket that holds Terraform remote state for the
# main `poc` configuration. This config uses LOCAL state (chicken-and-egg: it
# can't store its own state in a bucket it hasn't created yet).
#
# Run this ONCE, before the main config:
#   cd infra/terraform/bootstrap
#   terraform init
#   terraform apply
#
# Then use the printed bucket name in ../poc/backend.tf.
#
# State locking for the main config uses S3's native lockfile support
# (Terraform >= 1.10, `use_lockfile = true`) — no DynamoDB table required.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  # POC convenience: allow `terraform destroy` of the bootstrap to remove the
  # bucket even if state objects remain. Flip to false if you want protection.
  force_destroy = true

  tags = {
    Project   = "audio-recording-processor"
    Purpose   = "terraform-remote-state"
    ManagedBy = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
