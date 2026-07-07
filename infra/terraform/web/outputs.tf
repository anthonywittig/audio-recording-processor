output "web_url" {
  description = "The web app (stable as long as this stack persists)."
  value       = "https://${aws_cloudfront_distribution.web.domain_name}"
}

output "site_bucket" {
  description = "S3 bucket the built SPA is synced to."
  value       = aws_s3_bucket.site.bucket
}

output "distribution_id" {
  description = "CloudFront distribution id (for cache invalidation on deploy)."
  value       = aws_cloudfront_distribution.web.id
}

output "api_endpoint" {
  description = "Direct HTTP API endpoint (normally reached via CloudFront /api/*)."
  value       = aws_apigatewayv2_api.web.api_endpoint
}
