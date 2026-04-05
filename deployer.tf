#########################################
# Deployer IAM — optional
# Creates an IAM user + group + policy with the permissions needed to sync
# site content to the bucket and invalidate the CloudFront distribution.
# Intended for CI/CD. Disabled by default.
#########################################

locals {
  deployer_name = "${local.primary_domain}-deployer"
}

resource "aws_iam_group" "deployer" {
  count = var.create_deployer_iam ? 1 : 0
  name  = local.deployer_name
}

data "aws_iam_policy_document" "deployer" {
  count = var.create_deployer_iam ? 1 : 0

  statement {
    sid       = "ListAllBuckets"
    effect    = "Allow"
    actions   = ["s3:ListAllMyBuckets"]
    resources = ["*"]
  }

  statement {
    sid    = "SyncBucket"
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
    ]
    resources = [
      aws_s3_bucket.target.arn,
      "${aws_s3_bucket.target.arn}/*",
    ]
  }

  statement {
    sid    = "InvalidateCloudFront"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
      "cloudfront:ListInvalidations",
    ]
    resources = [aws_cloudfront_distribution.cdn.arn]
  }
}

resource "aws_iam_policy" "deployer" {
  count  = var.create_deployer_iam ? 1 : 0
  name   = "${local.deployer_name}-sync-permissions"
  policy = data.aws_iam_policy_document.deployer[0].json
  tags   = var.global-tags
}

resource "aws_iam_group_policy_attachment" "deployer" {
  count      = var.create_deployer_iam ? 1 : 0
  group      = aws_iam_group.deployer[0].name
  policy_arn = aws_iam_policy.deployer[0].arn
}

resource "aws_iam_user" "deployer" {
  count = var.create_deployer_iam ? 1 : 0
  name  = local.deployer_name
  tags  = var.global-tags
}

resource "aws_iam_user_group_membership" "deployer" {
  count = var.create_deployer_iam ? 1 : 0
  user  = aws_iam_user.deployer[0].name
  groups = [
    aws_iam_group.deployer[0].name,
  ]
}
