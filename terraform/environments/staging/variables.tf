variable "location" {
  type    = string
  default = "eastus2"
}
variable "monthly_budget" {
  type    = number
  default = 300
}
variable "alert_emails" {
  type    = list(string)
  default = []
}
variable "configure_github_oidc" {
  type    = bool
  default = false
}
variable "github_org" {
  type    = string
  default = ""
}
variable "github_repo" {
  type    = string
  default = "azure-zero-trust"
}
