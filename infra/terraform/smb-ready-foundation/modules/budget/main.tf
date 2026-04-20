// Cost Management Budget — sub scope.

resource "azurerm_consumption_budget_subscription" "monthly" {
  name            = "budget-smb-monthly"
  subscription_id = var.subscription_resource_id

  amount     = var.amount
  time_grain = "Monthly"

  time_period {
    start_date = "${var.start_date}T00:00:00Z"
  }

  notification {
    enabled        = true
    operator       = "GreaterThan"
    threshold      = 80
    threshold_type = "Forecasted"
    contact_emails = [var.alert_email]
  }

  notification {
    enabled        = true
    operator       = "GreaterThan"
    threshold      = 90
    threshold_type = "Actual"
    contact_emails = [var.alert_email]
  }

  notification {
    enabled        = true
    operator       = "GreaterThan"
    threshold      = 100
    threshold_type = "Actual"
    contact_emails = [var.alert_email]
  }

  lifecycle {
    ignore_changes = [time_period[0].end_date]
  }
}
