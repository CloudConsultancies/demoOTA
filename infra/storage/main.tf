# ---------------------------------------------------------------------------
# Storage of demoOTA: three private buckets with different lifetimes.
#
#   artifacts  RAUC bundles, SBOMs, CVE reports  versioned, kept
#   cache      Yocto downloads and sstate        expires, destroyable
#   records    audit log, per-device results     versioned, kept long-term
#
# Every bucket gets the same baseline (modules/private-bucket): SSE-S3,
# public access blocked, ACLs off, TLS only. One module call per bucket,
# so destroying the cache (make storage-destroy-cache) leaves the other
# buckets' settings alone.
# ---------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

locals {
  # Bucket names are global: the account ID makes them unique
  bucket_suffix = data.aws_caller_identity.current.account_id
}

# --- artifacts -------------------------------------------------------------

resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.name_prefix}-artifacts-${local.bucket_suffix}"

  # Released bundles and their evidence (SBOM, CVE report) are kept
  lifecycle {
    prevent_destroy = true
  }
}

module "artifacts_baseline" {
  source     = "./modules/private-bucket"
  bucket     = aws_s3_bucket.artifacts.id
  bucket_arn = aws_s3_bucket.artifacts.arn
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  # Overwritten or deleted versions are a safety net, not an archive
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.artifacts_noncurrent_days
    }
    expiration {
      expired_object_delete_marker = true
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.artifacts]
}

# --- cache -----------------------------------------------------------------

resource "aws_s3_bucket" "cache" {
  bucket = "${var.name_prefix}-cache-${local.bucket_suffix}"

  # Only a cache: destroy removes it with its contents, the next build
  # fills it again
  force_destroy = true
}

module "cache_baseline" {
  source     = "./modules/private-bucket"
  bucket     = aws_s3_bucket.cache.id
  bucket_arn = aws_s3_bucket.cache.arn
}

# Not versioned: an overwritten cache object needs no history
resource "aws_s3_bucket_lifecycle_configuration" "cache" {
  bucket = aws_s3_bucket.cache.id

  rule {
    id     = "expire-cache-objects"
    status = "Enabled"
    filter {}

    expiration {
      days = var.cache_expiration_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# --- records ---------------------------------------------------------------

resource "aws_s3_bucket" "records" {
  bucket = "${var.name_prefix}-records-${local.bucket_suffix}"

  # Audit evidence: kept long-term, never deleted by accident
  lifecycle {
    prevent_destroy = true
  }
}

module "records_baseline" {
  source     = "./modules/private-bucket"
  bucket     = aws_s3_bucket.records.id
  bucket_arn = aws_s3_bucket.records.arn
}

# Versions are kept: an overwritten or deleted record stays recoverable
resource "aws_s3_bucket_versioning" "records" {
  bucket = aws_s3_bucket.records.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "records" {
  bucket = aws_s3_bucket.records.id

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.records]
}
