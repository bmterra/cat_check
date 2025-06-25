########################################
# Random suffix for unique resource names
########################################
resource "random_pet" "suffix" {}

########################################
# S3 bucket for uploads
########################################
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
}

########################################
# DynamoDB table for cat check status
########################################
resource "aws_dynamodb_table" "cat_status" {
  name         = local.dynamodb_table_name
  hash_key     = "pic_id"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "pic_id"
    type = "S"
  }
}

########################################
# IAM roles & policies
########################################
# Assume‑role policy shared by both Lambdas
########################################
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ── s3_upload Lambda role ─────────────────────────────────────────────────────
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

# ── cat_status Lambda role ────────────────────────────────────────────────────
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
resource "aws_lambda_function" "s3_upload" {
  function_name = "s3_upload_${random_pet.suffix.id}"
  filename      = "${path.module}/../../../lambdas/s3_upload.zip"
  handler       = "s3_upload.lambda_handler"
  runtime       = "python3.11"
  role          = aws_iam_role.s3_upload_role.arn
  timeout       = 10

  environment {
    variables = {
      BUCKET_NAME = module.uploads_bucket.s3_bucket_id
    }
  }

  source_code_hash = filebase64sha256("${path.module}/../../../lambdas/s3_upload.zip")
}

resource "aws_lambda_function" "cat_status" {
  function_name = "cat_status_${random_pet.suffix.id}"
  filename      = "${path.module}/../../../lambdas/cat_status.zip"
  handler       = "cat_status.lambda_handler"
  runtime       = "python3.11"
  role          = aws_iam_role.cat_status_role.arn
  timeout       = 10

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.cat_status.name
    }
  }

  source_code_hash = filebase64sha256("${path.module}/../../../lambdas/cat_status.zip")
}

########################################
# API Gateway (HTTP API)
########################################
resource "aws_apigatewayv2_api" "cats_api" {
  name          = "cats_api_${random_pet.suffix.id}"
  protocol_type = "HTTP"
}

## Integrations
resource "aws_apigatewayv2_integration" "s3_upload_integration" {
  api_id                 = aws_apigatewayv2_api.cats_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.s3_upload.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "cat_status_integration" {
  api_id                 = aws_apigatewayv2_api.cats_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.cat_status.invoke_arn
  payload_format_version = "2.0"
}

## Routes
resource "aws_apigatewayv2_route" "s3_upload_route" {
  api_id    = aws_apigatewayv2_api.cats_api.id
  route_key = "GET /s3_upload"
  target    = "integrations/${aws_apigatewayv2_integration.s3_upload_integration.id}"
}

resource "aws_apigatewayv2_route" "cat_status_route" {
  api_id    = aws_apigatewayv2_api.cats_api.id
  route_key = "GET /cat_status"
  target    = "integrations/${aws_apigatewayv2_integration.cat_status_integration.id}"
}

## Permissions for API Gateway to invoke Lambdas
resource "aws_lambda_permission" "allow_api_gateway_invoke_s3_upload" {
  statement_id  = "AllowAPIGatewayInvokeS3Upload"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_upload.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.cats_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_api_gateway_invoke_cat_status" {
  statement_id  = "AllowAPIGatewayInvokeCatStatus"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cat_status.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.cats_api.execution_arn}/*/*"
}

## Stage
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.cats_api.id
  name        = "$default"
  auto_deploy = true
}

########################################
# Outputs
########################################
output "api_base_url" {
  description = "Base URL of the API Gateway."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "s3_upload_endpoint" {
  description = "Full URL for the s3_upload endpoint."
  value       = "${aws_apigatewayv2_stage.default.invoke_url}/s3_upload"
}

output "cat_status_endpoint" {
  description = "Full URL for the cat_status endpoint."
  value       = "${aws_apigatewayv2_stage.default.invoke_url}/cat_status"
}



################
# Compute
################


################
# API Gateway
################
