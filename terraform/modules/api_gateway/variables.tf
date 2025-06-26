variable "suffix" {
  description = "suffix used for naming"
  type = string
}

variable "s3_upload_lambda" {
  description = "s3 upload lambda"
  type = string
}

variable "cat_status_lambda" {
  description = "cat status lambda"
  type = string
}

variable "s3_upload_lambda_arn" {
  description = "s3 upload lambda arn"
  type = string
}

variable "cat_status_lambda_arn" {
    description = "cat status lambda arn"
  type = string
}
