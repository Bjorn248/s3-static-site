variable "root-domain" {
  # This is likely what users will type into the browser
  description = "The root domain for the static site. e.g. scca-classifier.com (without www.)"
  type        = string
}

variable "target-domain" {
  # This is where you want your redirect to end up. The target.
  # Leave unset (null) to serve content directly at the root/apex domain with no redirect.
  description = "The domain to redirect the root domain to (e.g. www.example.com). If null, content is served at the root domain and no redirect distribution is created."
  type        = string
  default     = null
}

variable "cloudfront-price-class" {
  description = "Which price class to use for the CloudFront distributions. One of PriceClass_All, PriceClass_200, PriceClass_100."
  type        = string
  default     = "PriceClass_All"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.cloudfront-price-class)
    error_message = "cloudfront-price-class must be one of PriceClass_All, PriceClass_200, or PriceClass_100."
  }
}

variable "global-tags" {
  description = "Global tags that will be added to every resource created by this module"
  type        = map(string)
  default     = {}
}

variable "enable_versioning" {
  description = "Enable S3 versioning on the target (content) bucket."
  type        = bool
  default     = false
}

variable "spa_mode" {
  description = "If true, CloudFront returns /index.html with status 200 for 403/404 responses (useful for single-page apps with client-side routing)."
  type        = bool
  default     = false
}
