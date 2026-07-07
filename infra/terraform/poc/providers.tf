provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

# Terraform manages only AWS here. The in-cluster side is deployed out-of-band:
# the Temporal server via the helm CLI (README "Temporal server") and the
# workers via k8s/apply.sh — so no kubernetes/helm providers are needed.
