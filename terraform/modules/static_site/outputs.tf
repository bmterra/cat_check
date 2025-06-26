output "bucket_id" {
  description = "Name of the S3 bucket hosting the site"
  value       = aws_s3_bucket.site.id
}

output "bucket_arn" {
  description = "Name of the S3 bucket hosting the site"
  value       = aws_s3_bucket.site.arn
}

output "bucket_regional_domain_name" {
  description = "Name of the S3 bucket hosting the site"
  value       = aws_s3_bucket.site.bucket_regional_domain_name
}