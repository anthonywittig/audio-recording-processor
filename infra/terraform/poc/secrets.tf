# Container for the OpenAI API key used by the summarize (Go) and action-items
# (Python) workers. Terraform owns ONLY the container — never the value, so the
# key never lands in git or Terraform state.
#
# Set / rotate the value out-of-band:
#   aws secretsmanager put-secret-value --secret-id arp/openai-api-key \
#     --secret-string 'sk-...' --region us-east-1
#
# If the secret was already created via the CLI before the first `terraform
# apply`, adopt it instead of recreating:
#   terraform import aws_secretsmanager_secret.openai arp/openai-api-key

resource "aws_secretsmanager_secret" "openai" {
  name = "${local.name}/openai-api-key"
  tags = local.common_tags
}

output "openai_secret_arn" {
  description = "Secrets Manager ARN for the OpenAI API key. Referenced by worker IRSA policies and OPENAI_SECRET_ID."
  value       = aws_secretsmanager_secret.openai.arn
}
