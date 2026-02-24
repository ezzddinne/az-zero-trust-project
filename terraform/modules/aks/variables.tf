variable "resource_group_name" {
  type = string
}

variable "resource_group_id" {
  description = "Resource group ID for role assignments"
  type        = string
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

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "aks_sku_tier" {
  description = "AKS SKU tier (Free or Standard)"
  type        = string
  default     = "Free"
}

variable "aks_admin_group_ids" {
  description = "Entra ID group IDs for AKS admin access"
  type        = list(string)
  default     = []
}

# Networking
variable "aks_system_subnet_id" {
  description = "Subnet ID for system node pool"
  type        = string
}

variable "aks_workload_subnet_id" {
  description = "Subnet ID for workload node pool"
  type        = string
}

variable "private_dns_zone_id" {
  description = "Private DNS zone ID for AKS private cluster"
  type        = string
  default     = null
}

variable "create_dns_role_assignment" {
  description = "Whether to create DNS role assignment (set to true after private DNS zone is created)"
  type        = bool
  default     = false
}

variable "enable_private_cluster" {
  description = "Enable private cluster (API server not exposed to internet)"
  type        = bool
  default     = true
}

variable "enable_local_accounts" {
  description = "Enable local accounts for easier debugging (disable for production)"
  type        = bool
  default     = false
}

variable "network_plugin" {
  description = "Network plugin: azure (advanced) or kubenet (simple/faster)"
  type        = string
  default     = "azure"
  validation {
    condition     = contains(["azure", "kubenet"], var.network_plugin)
    error_message = "network_plugin must be either 'azure' or 'kubenet'"
  }
}

variable "network_policy" {
  description = "Network policy: calico (advanced) or null (simple/faster)"
  type        = string
  default     = "calico"
}

variable "deploy_firewall" {
  description = "Whether Azure Firewall is deployed (affects outbound type)"
  type        = bool
  default     = false
}

# System Node Pool
variable "system_node_vm_size" {
  description = "VM size for system node pool"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "system_node_autoscale" {
  description = "Enable autoscaling for system node pool"
  type        = bool
  default     = false
}

variable "system_node_count" {
  description = "Fixed node count (when autoscale disabled)"
  type        = number
  default     = 1
}

variable "system_node_min" {
  description = "Min nodes (when autoscale enabled)"
  type        = number
  default     = 1
}

variable "system_node_max" {
  description = "Max nodes (when autoscale enabled)"
  type        = number
  default     = 3
}

# Workload Node Pool
variable "deploy_workload_pool" {
  description = "Deploy dedicated workload node pool (disable if quota limited)"
  type        = bool
  default     = true
}

variable "workload_node_vm_size" {
  description = "VM size for workload node pool"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "workload_node_min" {
  description = "Min nodes for workload pool"
  type        = number
  default     = 1
}

variable "workload_node_max" {
  description = "Max nodes for workload pool"
  type        = number
  default     = 5
}

variable "use_spot_nodes" {
  description = "Use spot instances for workload nodes (cost saving)"
  type        = bool
  default     = false
}

# Monitoring Node Pool
variable "deploy_monitoring_pool" {
  description = "Deploy dedicated monitoring node pool"
  type        = bool
  default     = false
}

variable "monitoring_node_vm_size" {
  description = "VM size for monitoring node pool"
  type        = string
  default     = "Standard_D2s_v3"
}

# ACR
variable "acr_id" {
  description = "ACR resource ID for kubelet pull access"
  type        = string
  default     = ""
}

variable "create_acr_pull_assignment" {
  description = "Whether to create ACR pull role assignment (set to true after ACR is created)"
  type        = bool
  default     = false
}

# Monitoring
variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for diagnostics"
  type        = string
}
