# Values to store as GitHub repository variables
# (Settings -> Secrets and variables -> Actions -> Variables). None is secret.
output "github_variables" {
  description = "GitHub Actions repository variables"
  value = {
    AWS_REGION          = var.region
    AWS_PLAN_ROLE_ARN   = aws_iam_role.plan.arn
    AWS_APPLY_ROLE_ARN  = aws_iam_role.apply.arn
    AWS_TFSTATE_BUCKET  = aws_s3_bucket.tfstate.bucket
    AWS_BOUNDARY_POLICY = aws_iam_policy.boundary.arn
  }
}

output "github_oidc_provider_arn" {
  description = "GitHub OIDC provider used by the roles"
  value       = local.github_oidc_provider_arn
}

output "github_oidc_provider_owner" {
  description = "Which stack owns (created) the shared GitHub OIDC provider"
  value       = var.create_github_oidc_provider ? "demoOTA (this stack)" : "another stack (referenced via data source)"
}
