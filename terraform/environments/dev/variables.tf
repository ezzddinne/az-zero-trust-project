variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus2"
}

variable "monthly_budget" {
  description = "Monthly budget in USD"
  type        = number
  default     = 150
}

variable "alert_emails" {
  description = "Email addresses for budget/security alerts"
  type        = list(string)
  default     = []
}

variable "configure_github_oidc" {
  description = "Configure GitHub OIDC federation"
  type        = bool
  default     = false
}

variable "github_org" {
  description = "GitHub organization"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "azure-zero-trust"
}
