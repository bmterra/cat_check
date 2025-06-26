output "cdn_domain" {
  description = "CloudFront domain to access the Website and API"
  value       = aws_cloudfront_distribution.cdn.domain_name
}
