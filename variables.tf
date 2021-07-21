variable "root-domain" {
  # This is likely what users will type into the browser
  description = "The root domain for the static site. e.g. scca-classifier.com (without www.)"
  type        = string
}

variable "target-domain" {
  # This is where you want your redirect to end up. The target.
  description = "The domain to redirect to from the root domain (e.g. www.scca-classifier.com)"
  type        = string
}

variable "cloudfront-price-class" {
  # Can be either PriceClass_All, PriceClass_200, or PriceClass_100
  # See https://aws.amazon.com/cloudfront/pricing/ for more detail
  description = "Which price class to use for the cloudfront distribution"
  type        = string
  default     = "PriceClass_All"
}

variable "global-tags" {
  description = "Global tags that will be added to every resource created by this module"
  default     = {}
  type        = map(string)
}
