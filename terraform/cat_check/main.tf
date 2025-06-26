
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

# DynamoDB table for cat check status
resource "aws_dynamodb_table" "cat_status" {
  name         = local.dynamodb_table_name
  hash_key     = "pic_id"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "pic_id"
    type = "S"
  }
}


# Assume‑role policy for both Lambdas
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# s3_upload Lambda role
resource "aws_iam_role" "s3_upload_role" {
  name               = "lambda_s3_upload_role_${random_pet.suffix.id}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "s3_upload_logs" {
  role       = aws_iam_role.s3_upload_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetObject"
    ]
    resources = ["${module.uploads_bucket.s3_bucket_arn}/*"]
  }
}

resource "aws_iam_policy" "s3_policy" {
  name   = "lambda_s3_upload_policy_${random_pet.suffix.id}"
  policy = data.aws_iam_policy_document.s3_policy.json
}

resource "aws_iam_role_policy_attachment" "s3_upload_policy_attach" {
  role       = aws_iam_role.s3_upload_role.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

# cat_status Lambda role
resource "aws_iam_role" "cat_status_role" {
  name               = "lambda_cat_status_role_${random_pet.suffix.id}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "cat_status_logs" {
  role       = aws_iam_role.cat_status_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "dynamodb_policy" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [aws_dynamodb_table.cat_status.arn]
  }
}

resource "aws_iam_policy" "dynamodb_policy" {
  name   = "lambda_cat_status_policy_${random_pet.suffix.id}"
  policy = data.aws_iam_policy_document.dynamodb_policy.json
}

resource "aws_iam_role_policy_attachment" "cat_status_policy_attach" {
  role       = aws_iam_role.cat_status_role.name
  policy_arn = aws_iam_policy.dynamodb_policy.arn
}

########################################
# Lambda functions
########################################
locals {
  s3_upload_file = "${path.module}/../../lambdas/s3_upload.zip"
  cat_status_file = "${path.module}/../../lambdas/cat_status.zip"
}

data "archive_file" "zip_s3_upload" {
	source_dir = "${path.module}/../../lambdas/s3_upload"
	type = "zip"
	output_path = local.s3_upload_file
}

resource "aws_lambda_function" "s3_upload" {
  function_name = "s3_upload_${random_pet.suffix.id}"
  filename      = local.s3_upload_file
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  role          = aws_iam_role.s3_upload_role.arn
  timeout       = 10

  environment {
    variables = {
      BUCKET_NAME = module.uploads_bucket.s3_bucket_id
    }
  }

  source_code_hash = data.archive_file.zip_s3_upload.output_sha256
}

data "archive_file" "cat_status_upload" {
	source_dir = "${path.module}/../../lambdas/cat_status"
	type = "zip"
	output_path = local.cat_status_file
}

resource "aws_lambda_function" "cat_status" {
  function_name = "cat_status_${random_pet.suffix.id}"
  filename      = local.cat_status_file
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  role          = aws_iam_role.cat_status_role.arn
  timeout       = 10

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.cat_status.name
    }
  }

  source_code_hash = data.archive_file.cat_status_upload.output_sha256
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
