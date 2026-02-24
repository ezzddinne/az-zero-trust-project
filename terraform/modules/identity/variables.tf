variable "environment" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}

variable "resource_group_id" {
  description = "Resource Group ID for RBAC assignments"
  type        = string
}

variable "aks_cluster_id" {
  description = "AKS Cluster ID for RBAC assignments"
  type        = string
  default     = ""
}

variable "create_aks_role_assignments" {
  description = "Whether to create AKS role assignments (set to true after AKS is created)"
  type        = bool
  default     = false
}

variable "aks_oidc_issuer_url" {
  description = "AKS OIDC issuer URL for Workload Identity"
  type        = string
  default     = ""
}

variable "create_federated_credentials" {
  description = "Whether to create federated identity credentials (set to true after AKS is created)"
  type        = bool
  default     = false
}

variable "workload_identities" {
  description = "Map of workload identities to create"
  type = map(object({
    namespace       = string
    service_account = string
  }))
  default = {}
}

variable "configure_github_oidc" {
  description = "Configure GitHub Actions OIDC federation"
  type        = bool
  default     = false
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = ""
}

variable "create_azuread_resources" {
  description = "Whether to create Azure AD groups and applications (requires Microsoft Graph permissions)"
  type        = bool
  default     = true
}
