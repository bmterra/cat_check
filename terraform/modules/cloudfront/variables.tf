variable "bucket_id" {
  description = "Globally unique bucket name for the static site"
  type        = string
}

variable "bucket_regional_domain_name" {
  type = string
}

variable "bucket_arn" {
  description = "Globally unique bucket arn for the static site"
  type        = string
}

variable "api_endpoint_id" {
    type = string
}

variable "aws_region" {
  type = string
}