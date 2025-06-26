
# API Gateway (HTTP API)
resource "aws_apigatewayv2_api" "cats_api" {
  name          = "cats_api_${var.suffix}"
  protocol_type = "HTTP"

  # TODO: close this down
  cors_configuration {
    allow_origins = ["*"]            # site domain
    allow_methods = ["GET"]          # (OPTIONS is implied)
    allow_headers = ["content-type"] # browsers
    max_age       = 300              # cache pre-flight response
  }
}

## Integrations
resource "aws_apigatewayv2_integration" "s3_upload_integration" {
  api_id                 = aws_apigatewayv2_api.cats_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.s3_upload_lambda_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "cat_status_integration" {
  api_id                 = aws_apigatewayv2_api.cats_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.cat_status_lambda_arn
  payload_format_version = "2.0"
}

## Routes
resource "aws_apigatewayv2_route" "s3_upload_route" {
  api_id    = aws_apigatewayv2_api.cats_api.id
  route_key = "GET /api/s3_upload"
  target    = "integrations/${aws_apigatewayv2_integration.s3_upload_integration.id}"
}

resource "aws_apigatewayv2_route" "cat_status_route" {
  api_id    = aws_apigatewayv2_api.cats_api.id
  route_key = "GET /api/cat_status"
  target    = "integrations/${aws_apigatewayv2_integration.cat_status_integration.id}"
}

## Permissions for API Gateway to invoke Lambdas
resource "aws_lambda_permission" "allow_api_gateway_invoke_s3_upload" {
  statement_id  = "AllowAPIGatewayInvokeS3Upload"
  action        = "lambda:InvokeFunction"
  function_name = var.s3_upload_lambda
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.cats_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_api_gateway_invoke_cat_status" {
  statement_id  = "AllowAPIGatewayInvokeCatStatus"
  action        = "lambda:InvokeFunction"
  function_name = var.cat_status_lambda
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.cats_api.execution_arn}/*/*"
}

## Stage
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.cats_api.id
  name        = "$default"
  auto_deploy = true
}

