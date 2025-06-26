# S3 Bucket & Website configuration
resource "aws_s3_bucket" "site" {
  bucket        = var.bucket_name
  force_destroy = true
}

# Upload static assets to S3
locals {
  asset_files = fileset(var.content_dir, "**")
}

resource "aws_s3_object" "assets" {
  for_each = { for f in local.asset_files : f => f }

  bucket = aws_s3_bucket.site.id
  key    = each.value
  source = "${var.content_dir}/${each.value}"
  etag   = filemd5("${var.content_dir}/${each.value}")

  content_type = lookup({
    html = "text/html",
    css  = "text/css",
    js   = "application/javascript",
    json = "application/json",
    png  = "image/png",
    jpg  = "image/jpeg",
    jpeg = "image/jpeg",
    svg  = "image/svg+xml",
    ico  = "image/x-icon"
  }, element(split(".", each.value), length(split(".", each.value)) - 1), "binary/octet-stream")


}

# Runtime config of the API base URL
resource "aws_s3_object" "runtime_config" {
  bucket       = aws_s3_bucket.site.id
  key          = "config.js"
  content      = "window.__CONFIG__ = { API_BASE_URL: \"${var.api_base_url}\" };"
  content_type = "application/javascript"
}
