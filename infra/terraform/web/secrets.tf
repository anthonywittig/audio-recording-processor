# Container for the web app's shared passcode. Terraform owns ONLY the
# container — never the value, so it never lands in git or Terraform state
# (same pattern as arp/openai-api-key in ../poc).
#
# Set / rotate the value out-of-band:
#   aws secretsmanager put-secret-value --secret-id arp/web-passcode \
#     --secret-string '<passcode>' --region us-east-1

resource "aws_secretsmanager_secret" "web_passcode" {
  name = "arp/web-passcode"
}

output "web_passcode_secret_arn" {
  description = "Secrets Manager ARN for the web app passcode. Value set out-of-band."
  value       = aws_secretsmanager_secret.web_passcode.arn
}
