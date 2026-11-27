# ---------------------------------------------------------------------------
# Cost guard: a monthly budget for everything tagged Project=demoOTA, with
# email alerts on the forecast. The tag filter sees costs only once
# "Project" is an active cost allocation tag (README.md). Until then the
# account-wide budget of demoKubernetesCluster is the safety net.
# ---------------------------------------------------------------------------
resource "aws_budgets_budget" "demo" {
  name         = "${var.name_prefix}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name = "TagKeyValue"
    # Cost Explorer's tag filter format: user:<key>$<value>
    values = [format("user:Project$%s", var.project_tag)]
  }

  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "FORECASTED"
      subscriber_email_addresses = [var.budget_email]
    }
  }
}
