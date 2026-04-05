# s3-static-site
Terraform module that creates the resources related to hosting a static site on AWS.

## Behavior
This Terraform module supports two modes:

**Apex + redirect** (set `target-domain`): content is served at `target-domain` (e.g. `www.example.com`) and the apex (`example.com`) 301-redirects to it.

**Apex-only** (leave `target-domain` unset): content is served directly at the root domain (e.g. `example.com`) — no redirect distribution is created.

Resources created:

* 1 ACM certificate (in `us-east-1`, covering the content domain, plus the apex as a SAN in redirect mode)
* 1 S3 bucket — private, served via CloudFront using an Origin Access Control (OAC)
* 1 or 2 CloudFront distributions
  * A content distribution in front of the bucket (HTTPS, HTTP/3, IPv6, managed caching + security-headers policies)
  * *(apex + redirect mode only)* An apex-redirect distribution that 301-redirects the naked domain to the target via a CloudFront Function — no additional bucket required
* 2 or 4 Route53 alias records (A + AAAA for the content domain, plus A + AAAA for the apex in redirect mode)
* *(optional, when `create_deployer_iam = true`)* An IAM user + group + policy granting the permissions needed to sync content to the bucket and invalidate the CloudFront distribution (intended for CI/CD)

## Pre-Requisites
* A domain registered with a DNS provider
* A public hosted zone already configured in Route53 for that domain

## Requirements

| Name      | Version       |
| --------- | ------------- |
| terraform | >= 1.5.0      |
| aws       | >= 5.0, < 7.0 |

## Usage

Apex + www redirect:

```hcl
module "s3-static-site" {
  source = "github.com/Bjorn248/s3-static-site"

  root-domain            = "example.com"
  target-domain          = "www.example.com"
  cloudfront-price-class = "PriceClass_100"

  global-tags = {
    project = "my-site"
  }
}
```

Apex-only (serve content directly at the root domain):

```hcl
module "s3-static-site" {
  source = "github.com/Bjorn248/s3-static-site"

  root-domain            = "babyfelix.party"
  cloudfront-price-class = "PriceClass_100"
}
```

## Inputs

| Name                   | Description                                                                                                        | Type          | Default          | Required |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------ | :-----------: | :--------------: | :------: |
| root-domain            | Naked domain for the website (e.g. `example.com`).                                                                 | `string`      | —                | yes      |
| target-domain          | Target of the naked-domain redirect (e.g. `www.example.com`). Leave unset to serve content at the root domain.     | `string`      | `null`           | no       |
| cloudfront-price-class | CloudFront price class. One of `PriceClass_All`, `PriceClass_200`, `PriceClass_100`.                               | `string`      | `PriceClass_All` | no       |
| global-tags            | Tags applied to all resources created by this module.                                                              | `map(string)` | `{}`             | no       |
| enable_versioning      | Enable S3 versioning on the content bucket.                                                                        | `bool`        | `false`          | no       |
| spa_mode               | Return `/index.html` with HTTP 200 for 403/404 responses (useful for SPAs with client-side routing).               | `bool`        | `false`          | no       |
| create_deployer_iam    | Create an IAM user/group/policy with permissions to sync the bucket and invalidate CloudFront (for CI/CD).         | `bool`        | `false`          | no       |

## Outputs

| Name                        | Description                                                              |
| --------------------------- | ------------------------------------------------------------------------ |
| s3_bucket_name              | Name of the content bucket.                                              |
| s3_bucket_arn               | ARN of the content bucket.                                               |
| website_url                 | URL of the static site.                                                  |
| cloudfront_distribution_id  | CloudFront distribution ID (use for cache invalidation in CI/CD).        |
| cloudfront_distribution_arn | CloudFront distribution ARN.                                             |
| cloudfront_domain_name      | CloudFront-assigned domain name of the content distribution.             |
| acm_certificate_arn         | ARN of the ACM certificate used by CloudFront.                           |
| deployer_iam_user_name      | Name of the deployer IAM user (null unless `create_deployer_iam`).       |
| deployer_iam_user_arn       | ARN of the deployer IAM user (null unless `create_deployer_iam`).        |
| deployer_iam_group_name     | Name of the deployer IAM group (null unless `create_deployer_iam`).      |
| deployer_iam_policy_arn     | ARN of the deployer IAM policy (null unless `create_deployer_iam`).      |
