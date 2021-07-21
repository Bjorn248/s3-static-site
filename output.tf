output "s3_bucket_arn" {
  description = <<EOF
  ARN of the bucket containing the website files, to be used by iam module to create
  a policy that provides access to the bucket
  EOF
  value       = aws_s3_bucket.target.arn
}

output "website_url" {
  description = "URL of static site"
  value       = "https://${aws_route53_record.target_record.fqdn}"
}
