output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "update_kubeconfig_command" {
  description = "Run this to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "ecr_repository_urls" {
  description = "Push targets for each service image."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "db_secret_arn" {
  description = "Secrets Manager ARN holding the Temporal Postgres connection info."
  value       = aws_secretsmanager_secret.db.arn
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN for the cluster (used by IRSA)."
  value       = module.eks.oidc_provider_arn
}
