output "s3_bucket_name" {
  description = <<EOF
  Name of the bucket containing the website files, to be used by iam module to create
  a policy that provides access to the bucket
  EOF
  value       = aws_s3_bucket.target.id
}

output "website_url" {
  description = "URL of static site"
  value       = "https://${aws_route53_record.target_record.fqdn}"
}
