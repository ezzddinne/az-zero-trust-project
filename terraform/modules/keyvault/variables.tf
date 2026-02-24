variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "environment" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "unique_suffix" {
  description = "Unique suffix for globally unique Key Vault name"
  type        = string
}

variable "key_vault_sku" {
  description = "Key Vault SKU (standard or premium)"
  type        = string
  default     = "standard"
}

variable "pe_subnet_id" {
  description = "Subnet ID for Private Endpoint"
  type        = string
}

variable "keyvault_private_dns_zone_id" {
  description = "Private DNS Zone ID for Key Vault"
  type        = string
}

variable "workload_identity_principal_ids" {
  description = "Map of workload identity principal IDs to grant Key Vault Secrets User"
  type        = map(string)
  default     = {}
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID"
  type        = string
}

variable "create_sample_secrets" {
  description = "Create sample secrets for testing"
  type        = bool
  default     = false
}

variable "allowed_ip_addresses" {
  description = "List of IP addresses allowed to access Key Vault"
  type        = list(string)
  default     = []
}
