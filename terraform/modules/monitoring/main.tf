# -----------------------------------------------------
# Monitoring Module — Log Analytics + Diagnostic Settings
# Zero Trust: Continuous Verification
# -----------------------------------------------------

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-zt-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.retention_days

  # Cost control: daily cap
  daily_quota_gb = var.daily_quota_gb

  tags = var.tags
}

# --- Budget Alert ---
resource "azurerm_consumption_budget_resource_group" "main" {
  count             = var.monthly_budget > 0 ? 1 : 0
  name              = "budget-${var.environment}"
  resource_group_id = var.resource_group_id
  amount            = var.monthly_budget
  time_grain        = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }

  notification {
    enabled        = true
    operator       = "GreaterThanOrEqualTo"
    threshold      = 80
    contact_emails = var.alert_emails
  }

  notification {
    enabled        = true
    operator       = "GreaterThanOrEqualTo"
    threshold      = 100
    contact_emails = var.alert_emails
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}
