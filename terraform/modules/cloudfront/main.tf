

###############################################################################
# (3) Managed cache policies (no need to remember the IDs)
###############################################################################
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_caller_identity" "current" {}

###############################################################################
# (4) CloudFront distribution with two origins & behaviours
###############################################################################
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  default_root_object = "index.html"

  # Origins: S3 + API
  origin {
    origin_id   = "cat-s3-origin"
    domain_name = var.bucket_regional_domain_name
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  origin {
    origin_id   = "cat-api-origin"
    domain_name = "${var.api_endpoint_id}.execute-api.${var.aws_region}.amazonaws.com"
    origin_path = "" # (leave blank for root stage)
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Caches definitions
  default_cache_behavior {
    target_origin_id       = "cat-s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.disabled.id
  }

  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "cat-api-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = aws_cloudfront_cache_policy.api.id # no caching + forward queries
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true # swap for ACM for custom domain
  }
}

resource "aws_cloudfront_cache_policy" "api" {
  name        = "api-custom-policy"
  comment     = "API query passthrough"
  default_ttl = 5
  max_ttl     = 10
  min_ttl     = 0
  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "all"
    }
  }
}

# Create Origin Access Identity (for OAI approach)
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for S3"
}

# Attach a bucket policy so only CloudFront (the OAI) can read the objects
data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${var.bucket_arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.oai.iam_arn]
    }

    #condition {
    #  test     = "StringEquals"
    #  variable = "AWS:SourceAccount"
    #  values   = [data.aws_caller_identity.current.account_id]
    #}
  }
}


resource "aws_s3_bucket_policy" "example" {
  bucket = var.bucket_id
  policy = data.aws_iam_policy_document.s3_policy.json
}
