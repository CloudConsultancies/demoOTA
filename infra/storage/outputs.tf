output "bucket_names" {
  description = "Bucket names by purpose"
  value = {
    artifacts = aws_s3_bucket.artifacts.bucket
    cache     = aws_s3_bucket.cache.bucket
    records   = aws_s3_bucket.records.bucket
  }
}

# Stored as GitHub repository variables by make storage-github-vars.
# None is secret.
output "github_variables" {
  description = "GitHub Actions repository variables"
  value = {
    AWS_ARTIFACTS_BUCKET = aws_s3_bucket.artifacts.bucket
    AWS_CACHE_BUCKET     = aws_s3_bucket.cache.bucket
    AWS_RECORDS_BUCKET   = aws_s3_bucket.records.bucket
  }
}
