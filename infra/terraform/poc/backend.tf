# Remote state in the S3 bucket created by ../bootstrap.
#
# The bucket name is NOT hardcoded here — Terraform backend blocks can't use
# variables, so it's supplied as a PARTIAL backend at init time from the shared,
# gitignored ../backend.hcl (copy ../backend.hcl.example). After the bootstrap
# apply prints state_bucket_name, put it there once and run:
#   terraform init -backend-config=../backend.hcl
#
# `use_lockfile = true` enables S3-native state locking (Terraform >= 1.10),
# so no DynamoDB table is needed.

terraform {
  backend "s3" {
    key          = "poc/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
