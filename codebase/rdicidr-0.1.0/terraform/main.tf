data "aws_caller_identity" "current" {}

data "aws_canonical_user_id" "current" {}

locals {
  # AWS account ID makes S3 bucket names globally unique.
  account_id = data.aws_caller_identity.current.account_id

  name_prefix = "${var.project_name}-${var.environment}"

  application_bucket_name = "${local.name_prefix}-app-${local.account_id}"
  log_bucket_name         = "${local.name_prefix}-cloudfront-logs-${local.account_id}"

  cloudfront_origin_id = "${local.name_prefix}-s3-origin"

  # Canonical user ID used by CloudFront legacy access-log delivery.
  cloudfront_log_delivery_canonical_user_id = "c4c1ede66af53448b93c283ce9448c4ba468c9432aa01d700d3878632f77d2d0"
}

# -------------------------------------------------------------------
# Application S3 bucket
# -------------------------------------------------------------------

resource "aws_s3_bucket" "application" {
  bucket = local.application_bucket_name

  # Useful for a temporary assessment environment.
  # This allows Terraform destroy even when files exist.
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "application" {
  bucket = aws_s3_bucket.application.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "application" {
  bucket = aws_s3_bucket.application.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "application" {
  bucket = aws_s3_bucket.application.id

  rule {
    # Disables ACLs for the application bucket.
    # Access is controlled only by policies.
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "application" {
  bucket = aws_s3_bucket.application.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -------------------------------------------------------------------
# CloudFront access-log S3 bucket
# -------------------------------------------------------------------

resource "aws_s3_bucket" "logs" {
  bucket = local.log_bucket_name

  # Temporary challenge environment.
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = false
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    # CloudFront legacy logging requires ACL support.
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "logs" {
  depends_on = [
    aws_s3_bucket_ownership_controls.logs,
    aws_s3_bucket_public_access_block.logs
  ]

  bucket = aws_s3_bucket.logs.id

  access_control_policy {
    grant {
      grantee {
        id   = data.aws_canonical_user_id.current.id
        type = "CanonicalUser"
      }

      permission = "FULL_CONTROL"
    }

    grant {
      grantee {
        id   = local.cloudfront_log_delivery_canonical_user_id
        type = "CanonicalUser"
      }

      permission = "FULL_CONTROL"
    }

    owner {
      id = data.aws_canonical_user_id.current.id
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "delete-old-cloudfront-logs"
    status = "Enabled"

    filter {
      prefix = "cloudfront/${var.environment}/"
    }

    expiration {
      days = var.log_retention_days
    }
  }
}

# -------------------------------------------------------------------
# CloudFront Origin Access Control
# -------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "application" {
  name = "${local.name_prefix}-oac"

  description = "Allows CloudFront to access the private application bucket"

  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# -------------------------------------------------------------------
# CloudFront distribution
# -------------------------------------------------------------------

resource "aws_cloudfront_distribution" "application" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  # Lower-cost edge-location selection for the assessment.
  price_class = "PriceClass_100"

  origin {
    domain_name = aws_s3_bucket.application.bucket_regional_domain_name
    origin_id   = local.cloudfront_origin_id

    origin_access_control_id = aws_cloudfront_origin_access_control.application.id
  }

  default_cache_behavior {
    target_origin_id = local.cloudfront_origin_id

    allowed_methods = [
      "GET",
      "HEAD",
      "OPTIONS"
    ]

    cached_methods = [
      "GET",
      "HEAD"
    ]

    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  logging_config {
    bucket = aws_s3_bucket.logs.bucket_domain_name

    prefix = "cloudfront/${var.environment}/"

    include_cookies = false
  }

  # React client-side routes may return 403 from the private S3 origin.
  # Return index.html so React Router can handle the route.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  depends_on = [
    aws_s3_bucket_acl.logs
  ]
}

# -------------------------------------------------------------------
# Application bucket policy
# -------------------------------------------------------------------

data "aws_iam_policy_document" "application_bucket" {
  statement {
    sid    = "AllowCloudFrontReadOnly"
    effect = "Allow"

    principals {
      type = "Service"

      identifiers = [
        "cloudfront.amazonaws.com"
      ]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.application.arn}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"

      values = [
        aws_cloudfront_distribution.application.arn
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "application" {
  bucket = aws_s3_bucket.application.id
  policy = data.aws_iam_policy_document.application_bucket.json

  depends_on = [
    aws_s3_bucket_public_access_block.application
  ]
}