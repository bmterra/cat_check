output "endpoint" {
  description = "API Gateway Endpoint"
  value = aws_apigatewayv2_api.cats_check.api_endpoint
}

output "id" {
  description = "API Gateway Id"
  value = aws_apigatewayv2_api.cats_check.id
}
