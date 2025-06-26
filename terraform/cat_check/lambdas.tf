
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

# Lambda functions
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
