variable "region" {
  description = "AWS region. Must match the poc stack (the ingest bucket lives there)."
  type        = string
  default     = "us-east-1"
}
