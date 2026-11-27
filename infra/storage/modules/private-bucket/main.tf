# Baseline of every demoOTA bucket: SSE-S3, public access blocked, ACLs
# off, TLS only. The bucket itself (and its lifecycle) stays in the
# calling stack, so prevent_destroy and force_destroy can differ.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "bucket" {
  description = "Name (ID) of the bucket"
  type        = string
}

variable "bucket_arn" {
  description = "ARN of the bucket"
  type        = string
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = var.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3: free, no KMS key to pay for
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = var.bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = var.bucket
  rule {
    object_ownership = "BucketOwnerEnforced" # ACLs off
  }
}

# TLS only. Pre-signed URLs (devices, later) use HTTPS and still work.
data "aws_iam_policy_document" "tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [var.bucket_arn, "${var.bucket_arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = var.bucket
  policy = data.aws_iam_policy_document.tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}
