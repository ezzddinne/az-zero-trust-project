variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "environment" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}

variable "unique_suffix" {
  description = "Unique suffix for globally unique ACR name"
  type        = string
}

variable "acr_sku" {
  description = "ACR SKU (Basic, Standard, Premium)"
  type        = string
  default     = "Basic"
}

variable "pe_subnet_id" {
  description = "Subnet ID for Private Endpoint"
  type        = string
}

variable "acr_private_dns_zone_id" {
  description = "Private DNS Zone ID for ACR"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID"
  type        = string
}

variable "create_private_endpoint" {
  description = "Create private endpoint (requires Premium SKU)"
  type        = bool
  default     = true
}
