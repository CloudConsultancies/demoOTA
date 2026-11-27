# ---------------------------------------------------------------------------
# CI roles, assumed through GitHub OIDC. No long-lived keys exist.
#
#   demo-ota-plan   any branch of this repository, read-only
#   demo-ota-apply  main of this repository only, demoOTA resources only
#
# Trust is bound to the numeric owner and repository IDs. This repository
# uses GitHub's immutable OIDC subjects:
#   repo:CloudConsultancies@255329107/demoOTA@1472192666:ref:refs/heads/main
# A repository recreated under the same name gets a new ID and is refused.
# If the immutable-subject setting is turned off, both roles fail closed.
# ---------------------------------------------------------------------------
locals {
  sub_prefix = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repository}@${var.github_repository_id}"

  plan_role_name   = "${var.name_prefix}-plan"
  apply_role_name  = "${var.name_prefix}-apply"
  boundary_name    = "${var.name_prefix}-boundary"
  plan_role_arn    = "arn:aws:iam::${local.account_id}:role/${local.plan_role_name}"
  apply_role_arn   = "arn:aws:iam::${local.account_id}:role/${local.apply_role_name}"
  boundary_arn     = "arn:aws:iam::${local.account_id}:policy/${local.boundary_name}"
  budget_arn       = "arn:aws:budgets::${local.account_id}:budget/${aws_budgets_budget.demo.name}"
  bootstrap_state  = "${local.state_bucket_arn}/bootstrap/*"
  demo_bucket_arns = ["arn:aws:s3:::${var.name_prefix}-*", "arn:aws:s3:::${var.name_prefix}-*/*"]
  # Name-prefixed resources in this account, one pattern per service. IAM
  # does not accept a wildcard in the service part of an ARN, so each
  # service demoOTA uses is listed (var.named_services). The pattern
  # covers every ARN layout:
  #   arn:aws:sns:<region>:<acct>:demo-ota-x
  #   arn:aws:iam::<acct>:role/demo-ota-x
  #   arn:aws:logs:<region>:<acct>:log-group:demo-ota-x
  # Global services (IAM, Budgets) must have an empty region; IAM rejects
  # even a wildcard there. Regional ones get the demo region.
  global_services = ["iam", "budgets"]
  demo_resource_arns = [
    for svc in var.named_services :
    "arn:aws:${svc}:${contains(local.global_services, svc) ? "" : var.region}:${local.account_id}:*${var.name_prefix}-*"
  ]

  # Services without a region (their requests count as us-east-1)
  global_actions = [
    "iam:*", "sts:*", "budgets:*", "ce:*", "cur:*", "support:*",
    "health:*", "pricing:*", "account:Get*", "organizations:Describe*",
    "organizations:List*",
  ]
}

# --- Trust policies --------------------------------------------------------

data "aws_iam_policy_document" "trust_plan" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Any ref, pull request or environment of this repository
    condition {
      test     = "StringLike"
      variable = "${local.github_oidc_host}:sub"
      values   = ["${local.sub_prefix}:*"]
    }
  }
}

data "aws_iam_policy_document" "trust_apply" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Runs on main only (push, workflow_dispatch, schedule). Jobs that use
    # a GitHub environment get an ":environment:<name>" subject instead and
    # are refused too.
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = ["${local.sub_prefix}:ref:refs/heads/main"]
    }
  }
}

# --- Shared statements -----------------------------------------------------

# Both roles read through AWS's ReadOnlyAccess, which also covers data in
# other projects of this shared account (demoKubernetesCluster's state,
# parameters, secrets, logs). Those data reads are denied outside demoOTA,
# and the bootstrap's own state (it holds the budget email) is off limits.
data "aws_iam_policy_document" "deny_foreign_data" {
  statement {
    sid           = "DenyForeignObjectReads"
    effect        = "Deny"
    actions       = ["s3:GetObject*"]
    not_resources = ["arn:aws:s3:::${var.name_prefix}-*/*"]
  }
  statement {
    sid       = "DenyBootstrapState"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [local.bootstrap_state]
  }
  statement {
    sid    = "DenyForeignSecrets"
    effect = "Deny"
    actions = [
      "ssm:GetParameter*",
      "secretsmanager:GetSecretValue",
      "logs:GetLogEvents",
      "logs:FilterLogEvents",
      "logs:StartQuery",
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]
    not_resources = local.demo_resource_arns
  }
}

# --- demo-ota-plan ---------------------------------------------------------

resource "aws_iam_role" "plan" {
  name                 = local.plan_role_name
  description          = "GitHub Actions, any branch of ${var.github_owner}/${var.github_repository}: read-only (terraform plan)"
  assume_role_policy   = data.aws_iam_policy_document.trust_plan.json
  max_session_duration = 3600

  # The trust policy names the provider by its computed ARN (so the plan
  # shows it in full); create the provider first
  depends_on = [aws_iam_openid_connect_provider.github]
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan" {
  source_policy_documents = [data.aws_iam_policy_document.deny_foreign_data.json]

  # terraform plan takes the state lock: a lock file next to the state.
  # That is the only write; the state itself stays read-only.
  statement {
    sid       = "StateLockFiles"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket_arn}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "plan" {
  name   = "${local.plan_role_name}-scope"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan.json
}

# --- demo-ota-apply --------------------------------------------------------

# What any demoOTA writer may do: everything on demoOTA resources, found
# by name prefix or by the Project tag, and create new ones only with the
# Project tag. The apply role gets it inline; every role it creates must
# carry the same limits as its permissions boundary (see below), so a new
# role can never hold more than the apply role.
data "aws_iam_policy_document" "demo_scope" {
  statement {
    sid       = "DemoResourcesByName"
    actions   = ["*"]
    resources = concat(local.demo_bucket_arns, local.demo_resource_arns)
  }

  statement {
    sid       = "DemoResourcesByTag"
    actions   = ["*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_tag]
    }
  }

  # Only actions that take tags in the request (create and tag actions)
  # can match aws:RequestTag, so this does not open anything else.
  # Resources that already carry a Project tag are excluded, so a
  # resource of another project cannot be re-tagged into demoOTA.
  statement {
    sid       = "CreateWithProjectTag"
    actions   = ["*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_tag]
    }
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/Project"
      values   = ["true"]
    }
  }

  # Untagged resources of other projects: tagging them Project=demoOTA
  # would hand them to this role. Services whose resources have names
  # may tag only demo-ota-* resources. (Creating with tags also checks the
  # tag permission while the new resource has no tag yet, so a tag
  # condition would block creation.) Add a service here when a stack
  # starts using it.
  statement {
    sid    = "DenyTaggingForeignNamedResources"
    effect = "Deny"
    actions = [
      "iam:Tag*", "iam:Untag*",
      "s3:PutBucketTagging", "s3:DeleteBucketTagging",
      "logs:TagResource", "logs:UntagResource", "logs:TagLogGroup", "logs:UntagLogGroup",
      "sns:TagResource", "sns:UntagResource",
      "events:TagResource", "events:UntagResource",
      "cloudwatch:TagResource", "cloudwatch:UntagResource",
      "iot:TagResource", "iot:UntagResource",
    ]
    not_resources = concat(local.demo_bucket_arns, local.demo_resource_arns)
  }

  # EC2 resources have IDs, not names: only tag-on-create (ec2:CreateAction
  # set) or resources that already are demoOTA's
  statement {
    sid       = "DenyTaggingForeignEc2"
    effect    = "Deny"
    actions   = ["ec2:CreateTags", "ec2:DeleteTags"]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_tag]
    }
    condition {
      test     = "Null"
      variable = "ec2:CreateAction"
      values   = ["true"]
    }
  }

  # The bootstrap's own resources: readable, never changed from CI
  statement {
    sid    = "DenyChangingBootstrap"
    effect = "Deny"
    not_actions = [
      "iam:Get*", "iam:List*", "budgets:ViewBudget", "budgets:Describe*",
    ]
    resources = [
      local.plan_role_arn,
      local.apply_role_arn,
      local.boundary_arn,
      local.budget_arn,
      local.github_oidc_provider_arn,
    ]
  }

  statement {
    sid    = "DenyChangingStateBucket"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket*",
      "s3:PutBucket*",
      "s3:DeleteBucketPolicy",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:PutReplicationConfiguration",
    ]
    resources = [local.state_bucket_arn]
  }

  # Roles created by demoOTA must be capped by the boundary
  statement {
    sid       = "DenyRolesWithoutBoundary"
    effect    = "Deny"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.boundary_arn]
    }
  }

  # No long-lived credentials, ever
  statement {
    sid    = "DenyLongLivedCredentials"
    effect = "Deny"
    actions = [
      "iam:DeleteRolePermissionsBoundary",
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
      "iam:UploadSSHPublicKey",
      "iam:CreateServiceSpecificCredential",
    ]
    resources = ["*"]
  }

  # One region: nothing forgotten (and paid for) somewhere else
  statement {
    sid         = "DenyOtherRegions"
    effect      = "Deny"
    not_actions = local.global_actions
    resources   = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }
}

data "aws_iam_policy_document" "apply" {
  source_policy_documents = [
    data.aws_iam_policy_document.demo_scope.json,
    data.aws_iam_policy_document.deny_foreign_data.json,
  ]
}

resource "aws_iam_role" "apply" {
  name                 = local.apply_role_name
  description          = "GitHub Actions, main of ${var.github_owner}/${var.github_repository} only: manages demoOTA resources"
  assume_role_policy   = data.aws_iam_policy_document.trust_apply.json
  max_session_duration = 3600

  depends_on = [aws_iam_openid_connect_provider.github]
}

# terraform plan/apply refresh needs to read what it manages
resource "aws_iam_role_policy_attachment" "apply_readonly" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "apply" {
  name   = "${local.apply_role_name}-scope"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}

# --- Permissions boundary for roles demoOTA creates ------------------------

# The demo scope plus a small read set: a build host or device role gets
# no more than the apply role, and no account-wide read access. Extend
# the read set here (bootstrap change) when a later stack needs it.
data "aws_iam_policy_document" "boundary" {
  # No deny_foreign_data: roles under this boundary have no account-wide
  # read access, so other projects' data is not allowed in the first
  # place. Only the bootstrap state needs an explicit deny, because the
  # demo scope covers the state bucket by name.
  source_policy_documents = [data.aws_iam_policy_document.demo_scope.json]

  statement {
    sid       = "DenyBootstrapState"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [local.bootstrap_state]
  }

  statement {
    sid = "BasicReads"
    actions = [
      "sts:GetCallerIdentity",
      "ec2:Describe*",
      "s3:ListAllMyBuckets",
      "s3:GetBucketLocation",
      "cloudwatch:PutMetricData",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "boundary" {
  name        = local.boundary_name
  description = "Permissions boundary of every role created by demoOTA stacks"
  policy      = data.aws_iam_policy_document.boundary.json
}
