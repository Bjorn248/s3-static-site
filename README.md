# s3-static-site
Terraform module that creates the resources related to hosting a static site on AWS

## Behavior
This terraform module creates the following resources:

* 1 ACM Certificate
* 2 S3 buckets
  * A "root" bucket with just the naked domain (e.g. scca-classifier.com)
  * A "target" bucket with the www subdomain (e.g. www.scca-classifier.com)
* 1 Cloudfront Distribution pointing at the www bucket
* 2 Route53 Records
  * A root alias record pointing at the root bucket, which redirects to the www domain
  * A www alias record pointing at the cloudfront distribution

## Pre-Requisites
* A domain registered in Route53
* A hosted zone already configured in Route53 for your registered domain

## Usage

```
module "s3-static-site" {
  source = "github.com/Bjorn248/s3-static-site"

  root-domain            = "scca-classifier.com"
  target-domain          = "www.scca-classifier.com"
  cloudfront-price-class = "PriceClass_100"

  global-tags = {
    project = "scca-classifier"
  }
}
```

NOTE: I used `scca-classifier` as my example domain, since that was the driving
force behind making this modules. If you wish to use this module, please replace that
with the domain of your choice.

## Inputs

| Name                   | Description                                                                                                          | Type   | Default        | Required   |
| ------                 | -------------                                                                                                        | :----: | :-------:      | :--------: |
| root-domain            | Naked domain for the website (e.g., `scca-classifier.com`)                                                           | string | -              | yes        |
| target-domain          | Domain that will be the target of naked domain redirects (e.g., `www.example.com`). This is where users will end up. | string | -              | yes        |
| cloudfront-price-class | Which cloudfront price class to choose. See [this](https://aws.amazon.com/cloudfront/pricing/) page for more detail. | string | PriceClass_All | no         |
| global-tags            | A map of tags to apply to all resources created by this module                                                       | map    | -              | no         |

## Outputs

| Name          | Description                                                  |
| ------        | -------------                                                |
| s3_bucket_arn | The ARN of the S3 bucket containing the website source code. |
| website_url   | The URL of the static site                                   |
