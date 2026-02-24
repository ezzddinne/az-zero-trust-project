variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

# Hub VNet
variable "hub_address_space" {
  description = "Address space for Hub VNet"
  type        = string
  default     = "10.0.0.0/16"
}

variable "firewall_subnet_prefix" {
  description = "Address prefix for Azure Firewall subnet (min /26)"
  type        = string
  default     = "10.0.1.0/26"
}

variable "bastion_subnet_prefix" {
  description = "Address prefix for Azure Bastion subnet (min /26)"
  type        = string
  default     = "10.0.2.0/26"
}

variable "mgmt_subnet_prefix" {
  description = "Address prefix for management subnet (Tailscale/jumpbox VMs)"
  type        = string
  default     = "10.0.3.0/27"
}

variable "dns_subnet_prefix" {
  description = "Address prefix for DNS resolver subnet"
  type        = string
  default     = "10.0.4.0/28"
}

# AKS Spoke
variable "aks_spoke_address_space" {
  description = "Address space for AKS Spoke VNet"
  type        = string
  default     = "10.1.0.0/16"
}

variable "aks_system_subnet_prefix" {
  description = "Address prefix for AKS system node pool subnet"
  type        = string
  default     = "10.1.0.0/24"
}

variable "aks_workload_subnet_prefix" {
  description = "Address prefix for AKS workload node pool subnet"
  type        = string
  default     = "10.1.1.0/24"
}

variable "aks_lb_subnet_prefix" {
  description = "Address prefix for AKS internal load balancer subnet"
  type        = string
  default     = "10.1.2.0/24"
}

# Data Spoke
variable "data_spoke_address_space" {
  description = "Address space for Data Spoke VNet"
  type        = string
  default     = "10.2.0.0/16"
}

variable "pe_subnet_prefix" {
  description = "Address prefix for Private Endpoint subnet"
  type        = string
  default     = "10.2.1.0/24"
}

# Feature flags
variable "deploy_firewall" {
  description = "Deploy Azure Firewall (disable for dev to save cost)"
  type        = bool
  default     = false
}

variable "deploy_bastion" {
  description = "Deploy Azure Bastion"
  type        = bool
  default     = false
}

variable "firewall_sku_tier" {
  description = "Azure Firewall SKU tier (Standard or Premium)"
  type        = string
  default     = "Standard"
}
