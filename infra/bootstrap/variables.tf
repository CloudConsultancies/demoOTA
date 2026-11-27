variable "region" {
  description = "AWS region of the demo (shared with demoKubernetesCluster)"
  type        = string
  default     = "eu-north-1"
}

variable "name_prefix" {
  description = "Prefix of every demoOTA resource name; the apply role is scoped to it"
  type        = string
  default     = "demo-ota"
}

variable "project_tag" {
  description = "Value of the Project tag on every demoOTA resource"
  type        = string
  default     = "demoOTA"
}

variable "github_owner" {
  description = "GitHub owner (organisation) of this repository"
  type        = string
  default     = "CloudConsultancies"
}

variable "github_owner_id" {
  description = "Numeric ID of the GitHub owner (gh api repos/OWNER/REPO -q .owner.id)"
  type        = string
  default     = "255329107"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be numeric."
  }
}

variable "github_repository" {
  description = "Name of this repository (without the owner)"
  type        = string
  default     = "demoOTA"
}

variable "github_repository_id" {
  description = "Numeric ID of this repository (gh api repos/OWNER/REPO -q .id)"
  type        = string
  default     = "1472192666"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must be numeric, not owner/name."
  }
}

variable "named_services" {
  description = <<-EOT
    Regional services whose demo-ota-* named resources the apply role
    manages by name. S3 buckets, IAM (roles, policies, instance profiles)
    and Budgets are always included (roles.tf). IAM does not accept a
    wildcard service in a resource ARN, so add a service here when a stack
    starts using one whose resources have names.
  EOT
  type        = list(string)
  default = [
    "logs", "sns", "sqs", "events", "cloudwatch", "iot", "ssm",
    "secretsmanager", "kms", "dynamodb", "lambda", "ecr", "ec2",
  ]

  validation {
    condition = alltrue([
      for s in var.named_services :
      can(regex("^[a-z0-9-]+$", s)) && !contains(["iam", "budgets", "s3"], s)
    ])
    error_message = "named_services must be plain regional service prefixes such as \"logs\" (no wildcards; iam, budgets and s3 are handled in roles.tf)."
  }
}

variable "create_github_oidc_provider" {
  description = <<-EOT
    true: this stack creates the account's GitHub OIDC provider and owns it.
    false: an existing provider (created by another stack) is referenced
    with a data source.
    An account can hold only one provider for token.actions.githubusercontent.com.
    demoOTA owns it in the shared account (none existed on 2026-11-27);
    demoKubernetesCluster references it.
  EOT
  type        = bool
  default     = true
}

variable "budget_limit_usd" {
  description = "Monthly budget for costs tagged Project=demoOTA, in USD"
  type        = number
  default     = 10
}

variable "budget_email" {
  description = "Address that receives the budget alerts. Set it in terraform.tfvars (git-ignored), never commit it."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+$", var.budget_email))
    error_message = "budget_email must be an email address."
  }
}
