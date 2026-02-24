variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

variable "subnet_id" {
  description = "Subnet ID where the Tailscale VM will be deployed"
  type        = string
}

variable "vm_size" {
  description = "VM size for Tailscale gateway"
  type        = string
  default     = "Standard_D2s_v3" # 2 vCPU, 8 GB RAM - reliable performance
}

variable "admin_username" {
  description = "Admin username for VM"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "SSH public key for VM access (if empty, will generate new key)"
  type        = string
  default     = ""
}

variable "tailscale_authkey" {
  description = "Tailscale authentication key (optional - can be configured post-deployment)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "key_vault_id" {
  description = "Key Vault ID for storing generated SSH key (required if ssh_public_key is empty)"
  type        = string
  default     = null
}
