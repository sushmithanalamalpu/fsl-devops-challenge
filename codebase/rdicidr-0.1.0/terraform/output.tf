output "environment" {
  description = "Deployed environment."
  value       = var.environment
}

output "application_bucket_name" {
  description = "S3 bucket containing the React build."
  value       = aws_s3_bucket.application.bucket
}

output "logging_bucket_name" {
  description = "S3 bucket containing CloudFront access logs."
  value       = aws_s3_bucket.logs.bucket
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID."
  value       = aws_cloudfront_distribution.application.id
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name."
  value       = aws_cloudfront_distribution.application.domain_name
}

output "cloudfront_url" {
  description = "Public URL for the deployed application."
  value       = "https://${aws_cloudfront_distribution.application.domain_name}"
}