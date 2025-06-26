
# Random suffix for unique resource names
resource "random_pet" "suffix" {}

# Region
data "aws_region" "current" {}

# S3 bucket for uploads
module "uploads_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "cat-check-${random_pet.suffix.id}"

  # Allow deletion of non-empty bucket
  force_destroy = true

  lifecycle_rule = [
    {
      id      = "expire-after-30d"
      enabled = true
      expiration = {
        days = 30
      }
    }
  ]

  cors_rule = [{
    allowed_methods = ["PUT", "GET", "HEAD"]
    allowed_origins = ["*"] # Or restrict to your site/domain
    allowed_headers = ["*"]
    expose_headers  = []
    max_age_seconds = 3000
  }]
}    

# Enable eventbridge notifications
resource "aws_s3_bucket_notification" "uploads_bucket_notification" {
  bucket      = module.uploads_bucket.s3_bucket_id
  eventbridge = true
}

# DynamoDB table for check cat status
resource "aws_dynamodb_table" "cat_status" {
  name         = local.dynamodb_table_name
  hash_key     = "pic_id"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "pic_id"
    type = "S"
  }

  ttl {
    attribute_name = "TimeToExist"
    enabled        = true
  }
}

# API Gateway
module "api_gateway" {
  source = "../modules/api_gateway"
  suffix = random_pet.suffix.id
  s3_upload_lambda = aws_lambda_function.s3_upload.function_name
  s3_upload_lambda_arn =  aws_lambda_function.s3_upload.invoke_arn
  cat_status_lambda = aws_lambda_function.cat_status.function_name
  cat_status_lambda_arn =  aws_lambda_function.cat_status.invoke_arn
}

# Website
module "static_site" {
  source              = "../modules/static_site"
  bucket_name         = "cat-check-site-${random_pet.suffix.id}"
  api_base_url        = "/api"
  content_dir         = "${path.module}/../../static_website"
}

# CFD
module "cloudfront_distribution" {
  source              = "../modules/cloudfront"
  bucket_arn = module.static_site.bucket_arn
  bucket_id = module.static_site.bucket_id
  bucket_regional_domain_name = module.static_site.bucket_regional_domain_name
  api_endpoint_id = module.api_gateway.id
  aws_region = data.aws_region.current.region
}
