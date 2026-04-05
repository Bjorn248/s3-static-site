terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }
}

# ACM certs used by CloudFront must live in us-east-1.
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

locals {
  # Domain that actually serves the content. If target-domain isn't set,
  # content is served directly at the apex.
  primary_domain = var.target-domain != null ? var.target-domain : var.root-domain

  # Whether to create the apex-to-target redirect distribution.
  has_redirect = var.target-domain != null && var.target-domain != var.root-domain

  s3_origin_id = "s3-${local.primary_domain}"

  acm_sans = local.has_redirect ? [var.root-domain] : []
}

#########################################
# Content bucket — private, served via CloudFront + OAC
#########################################

resource "aws_s3_bucket" "target" {
  bucket = local.primary_domain
  tags   = var.global-tags
}

resource "aws_s3_bucket_public_access_block" "target" {
  bucket                  = aws_s3_bucket.target.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "target" {
  bucket = aws_s3_bucket.target.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "target" {
  bucket = aws_s3_bucket.target.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "target" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.target.id
  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "target" {
  statement {
    sid       = "AllowCloudFrontServicePrincipal"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.target.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "target" {
  bucket = aws_s3_bucket.target.id
  policy = data.aws_iam_policy_document.target.json
}

#########################################
# ACM certificate (us-east-1, for CloudFront)
#########################################

resource "aws_acm_certificate" "main" {
  provider                  = aws.us-east-1
  domain_name               = local.primary_domain
  subject_alternative_names = local.acm_sans
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [subject_alternative_names]
  }
}

data "aws_route53_zone" "main" {
  name         = var.root-domain
  private_zone = false
}

resource "aws_route53_record" "dvo_records" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "main" {
  provider                = aws.us-east-1
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.dvo_records : record.fqdn]
}

#########################################
# CloudFront — content distribution
#########################################

resource "aws_cloudfront_origin_access_control" "target" {
  name                              = "${local.primary_domain}-oac"
  description                       = "OAC for ${local.primary_domain}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Managed cache policy: CachingOptimized
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# Managed origin request policy: CORS-S3Origin
data "aws_cloudfront_origin_request_policy" "cors_s3" {
  name = "Managed-CORS-S3Origin"
}

# Managed response headers policy: SecurityHeadersPolicy
data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  default_root_object = "index.html"
  price_class         = var.cloudfront-price-class
  aliases             = [local.primary_domain]
  comment             = "Static site for ${local.primary_domain}"

  origin {
    domain_name              = aws_s3_bucket.target.bucket_regional_domain_name
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.target.id
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = local.s3_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.cors_s3.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.main.certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  dynamic "custom_error_response" {
    for_each = var.spa_mode ? [1] : []
    content {
      error_code            = 403
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 10
    }
  }

  dynamic "custom_error_response" {
    for_each = var.spa_mode ? [1] : []
    content {
      error_code            = 404
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 10
    }
  }

  tags = var.global-tags
}

#########################################
# CloudFront — apex-domain redirect (only when target-domain is set)
# A lightweight distribution that uses a CloudFront Function to 301-redirect
# the naked domain to the target domain. No second S3 bucket required.
#########################################

resource "aws_cloudfront_function" "apex_redirect" {
  count = local.has_redirect ? 1 : 0

  name    = replace("${var.root-domain}-apex-redirect", ".", "-")
  runtime = "cloudfront-js-2.0"
  comment = "Redirect ${var.root-domain} to https://${var.target-domain}"
  publish = true
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      return {
        statusCode: 301,
        statusDescription: 'Moved Permanently',
        headers: {
          'location': { value: 'https://${var.target-domain}' + request.uri }
        }
      };
    }
  EOT
}

resource "aws_cloudfront_distribution" "apex_redirect" {
  count = local.has_redirect ? 1 : 0

  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = var.cloudfront-price-class
  aliases         = [var.root-domain]
  comment         = "Redirect ${var.root-domain} -> ${var.target-domain}"

  # CloudFront requires at least one origin. The function returns before the
  # request is ever sent upstream, so this origin is never actually contacted.
  origin {
    domain_name              = aws_s3_bucket.target.bucket_regional_domain_name
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.target.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.apex_redirect[0].arn
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.main.certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = var.global-tags
}

#########################################
# Route53 alias records
#########################################

# Always created — points primary_domain at the content distribution.
# When apex-only (no target-domain), this IS the apex record.
resource "aws_route53_record" "target_record" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.primary_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "target_record_ipv6" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.primary_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

# Apex records pointing at the redirect distribution — only when target-domain is set.
resource "aws_route53_record" "root_record" {
  count = local.has_redirect ? 1 : 0

  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.root-domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.apex_redirect[0].domain_name
    zone_id                = aws_cloudfront_distribution.apex_redirect[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "root_record_ipv6" {
  count = local.has_redirect ? 1 : 0

  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.root-domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.apex_redirect[0].domain_name
    zone_id                = aws_cloudfront_distribution.apex_redirect[0].hosted_zone_id
    evaluate_target_health = false
  }
}
