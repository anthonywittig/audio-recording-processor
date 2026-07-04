variable "region" {
  description = "AWS region. Must support EKS, Bedrock, Transcribe, and SES."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Short name used to prefix/tag resources."
  type        = string
  default     = "arp" # audio-recording-processor
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "kubernetes_version" {
  description = "EKS control-plane Kubernetes version."
  type        = string
  default     = "1.34"
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed node group."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "db_instance_class" {
  description = "RDS instance class for the Temporal Postgres database."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  description = "Primary application database name (Temporal creates its own DBs too)."
  type        = string
  default     = "temporal"
}

variable "ecr_repositories" {
  description = "One ECR repo per container image we build."
  type        = list(string)
  default = [
    "workflow-ts",
    "intake-ts",
    "transcribe-java",
    "summarize-go",
    "action-items-py",
    "email-ruby",
  ]
}
