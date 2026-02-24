variable "resource_group_name" { type = string }
variable "resource_group_id" { type = string }
variable "location" { type = string }
variable "environment" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}

variable "log_analytics_sku" {
  description = "Log Analytics SKU"
  type        = string
  default     = "PerGB2018"
}

variable "retention_days" {
  description = "Log retention in days"
  type        = number
  default     = 30
}

variable "daily_quota_gb" {
  description = "Daily ingestion cap in GB (-1 for no cap)"
  type        = number
  default     = 1
}

variable "monthly_budget" {
  description = "Monthly budget in USD (0 to disable)"
  type        = number
  default     = 0
}

variable "alert_emails" {
  description = "Email addresses for budget alerts"
  type        = list(string)
  default     = []
}
