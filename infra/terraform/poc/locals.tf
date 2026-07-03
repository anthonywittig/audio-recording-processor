locals {
  name = var.project

  # Two AZs is plenty for a POC and keeps NAT/EIP costs down.
  azs = ["${var.region}a", "${var.region}b"]

  # Kubernetes namespaces.
  temporal_namespace = "temporal"
  app_namespace      = "arp"

  common_tags = {
    Project   = "audio-recording-processor"
    Env       = "poc"
    ManagedBy = "terraform"
  }
}
