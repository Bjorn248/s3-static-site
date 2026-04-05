output "s3_bucket_name" {
  description = "Name of the content bucket. Use this to grant your CI/CD role permissions to sync site files."
  value       = aws_s3_bucket.target.id
}

output "s3_bucket_arn" {
  description = "ARN of the content bucket."
  value       = aws_s3_bucket.target.arn
}

output "website_url" {
  description = "URL of the static site."
  value       = "https://${local.primary_domain}"
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution serving the site. Use this for cache invalidations from CI/CD."
  value       = aws_cloudfront_distribution.cdn.id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution serving the site."
  value       = aws_cloudfront_distribution.cdn.arn
}

output "cloudfront_domain_name" {
  description = "CloudFront-assigned domain name of the content distribution."
  value       = aws_cloudfront_distribution.cdn.domain_name
}

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate used by CloudFront."
  value       = aws_acm_certificate_validation.main.certificate_arn
}
