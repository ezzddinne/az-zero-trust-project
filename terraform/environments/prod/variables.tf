# Production environment variables
# This configuration is for the production environment with enhanced security and reliability
variable "location" {
  type    = string
  default = "eastus2"
}
variable "monthly_budget" {
  type    = number
  default = 600
}
variable "alert_emails" {
  type    = list(string)
  default = []
}
variable "configure_github_oidc" {
  type    = bool
  default = true
}
variable "github_org" {
  type    = string
  default = ""
}
variable "github_repo" {
  type    = string
  default = "azure-zero-trust"
}

