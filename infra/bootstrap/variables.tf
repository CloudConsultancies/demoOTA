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

variable "create_github_oidc_provider" {
  description = <<-EOT
    true: this stack creates the account's GitHub OIDC provider and owns it.
    false: an existing provider (created by another stack, for example
    demoKubernetesCluster's bootstrap) is referenced with a data source.
    An account can hold only one provider for token.actions.githubusercontent.com.
  EOT
  type        = bool
  default     = false
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
