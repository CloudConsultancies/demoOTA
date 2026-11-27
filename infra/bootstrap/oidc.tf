# ---------------------------------------------------------------------------
# GitHub OIDC provider. An account has only one provider for
# token.actions.githubusercontent.com, and demoOTA shares its account with
# demoKubernetesCluster. Exactly one of the two bootstraps owns it
# (create_github_oidc_provider = true); the other references it. README.md
# records which one owns it, so destroying the other one's bootstrap never
# breaks the owner's project.
# ---------------------------------------------------------------------------
locals {
  github_oidc_host = "token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://${local.github_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
  # No thumbprint_list: AWS checks GitHub's certificate against its own
  # library of trusted root CAs.

  # Shared with demoKubernetesCluster: a destroy of this stack never
  # removes it
  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://${local.github_oidc_host}"
}

locals {
  # A provider's ARN is fixed by account and host. Computing it (instead of
  # reading the new resource's arn) lets the plan show the trust and apply
  # policies in full; the roles depend on the provider for ordering.
  github_oidc_provider_arn = (
    var.create_github_oidc_provider
    ? "arn:aws:iam::${local.account_id}:oidc-provider/${local.github_oidc_host}"
    : data.aws_iam_openid_connect_provider.github[0].arn
  )
}
