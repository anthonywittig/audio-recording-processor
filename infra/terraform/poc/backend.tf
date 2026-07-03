# Remote state in the S3 bucket created by ../bootstrap.
#
# After running the bootstrap apply, set `bucket` below to the value it prints
# (default: audio-recording-processor-tfstate-awittig), then run:
#   terraform init
#
# `use_lockfile = true` enables S3-native state locking (Terraform >= 1.10),
# so no DynamoDB table is needed.

terraform {
  backend "s3" {
    bucket       = "audio-recording-processor-tfstate-awittig"
    key          = "poc/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
