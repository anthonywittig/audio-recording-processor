# Remote state in the same bootstrap bucket as ../poc, under its own key. This
# stack is PERSISTENT — it costs ~pennies idle (S3 + CloudFront + Lambda), so it
# survives the nightly `terraform destroy` of the poc stack and keeps a stable
# URL despite our DNS being managed by hand.
terraform {
  backend "s3" {
    bucket       = "audio-recording-processor-tfstate-awittig"
    key          = "web/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
