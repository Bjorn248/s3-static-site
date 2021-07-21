terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.50"
    }
  }
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

resource "aws_s3_bucket" "root" {
  bucket = var.root-domain
  acl    = "public-read"

  website {
    redirect_all_requests_to = "https://${var.target-domain}"
  }

  tags = var.global-tags
}

resource "aws_s3_bucket" "target" {
  bucket = var.target-domain
  acl    = "public-read"

  website {
    index_document = "index.html"
  }

  tags = var.global-tags
}

resource "aws_s3_bucket_policy" "allow_public_read" {
  bucket = aws_s3_bucket.target.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": [
        "${aws_s3_bucket.target.arn}/*"
      ]
    }
  ]
}
  EOF
}

resource "aws_acm_certificate" "main" {
  provider                  = aws.us-east-1
  subject_alternative_names = [var.target-domain, var.root-domain]
  domain_name               = var.root-domain
  validation_method         = "DNS"
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

locals {
  s3_origin_id = "S3Origin"
}

resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_s3_bucket.target.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
  }

  enabled = true

  default_root_object = "index.html"

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.main.certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
  }

  aliases = [var.target-domain]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"

    min_ttl     = "0"
    default_ttl = "300"
    max_ttl     = "1200"

    compress = true
  }

  price_class = var.cloudfront-price-class

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = var.global-tags
}

resource "aws_route53_record" "root_record" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.root-domain
  type    = "A"

  alias {
    name                   = aws_s3_bucket.root.website_domain
    zone_id                = aws_s3_bucket.root.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "target_record" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.target-domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}
