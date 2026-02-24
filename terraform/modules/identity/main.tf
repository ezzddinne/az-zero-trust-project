# -----------------------------------------------------
# Identity Module — Entra ID Groups, RBAC, Managed Identities
# Zero Trust: Verify Explicitly, Least Privilege
# -----------------------------------------------------

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# --- Entra ID Security Groups ---
resource "azuread_group" "aks_admins" {
  count            = var.create_azuread_resources ? 1 : 0
  display_name     = "zt-${var.environment}-aks-admins"
  security_enabled = true
  description      = "AKS cluster administrators for ${var.environment}"
}

resource "azuread_group" "aks_developers" {
  count            = var.create_azuread_resources ? 1 : 0
  display_name     = "zt-${var.environment}-aks-developers"
  security_enabled = true
  description      = "AKS developers with namespace-scoped access for ${var.environment}"
}

resource "azuread_group" "security_readers" {
  count            = var.create_azuread_resources ? 1 : 0
  display_name     = "zt-${var.environment}-security-readers"
  security_enabled = true
  description      = "Security team read access for ${var.environment}"
}

# --- RBAC: Subscription-level Reader (default for all) ---
resource "azurerm_role_assignment" "security_readers_sub" {
  count                = var.create_azuread_resources ? 1 : 0
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azuread_group.security_readers[0].object_id
}

# --- RBAC: Resource Group Contributor (scoped) ---
resource "azurerm_role_assignment" "aks_admins_rg" {
  count                = var.create_azuread_resources ? 1 : 0
  scope                = var.resource_group_id
  role_definition_name = "Contributor"
  principal_id         = azuread_group.aks_admins[0].object_id
}

# --- RBAC: AKS-specific roles ---
resource "azurerm_role_assignment" "aks_admins_cluster_admin" {
  count                = var.create_azuread_resources && var.create_aks_role_assignments ? 1 : 0
  scope                = var.aks_cluster_id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = azuread_group.aks_admins[0].object_id
}

resource "azurerm_role_assignment" "aks_developers_user" {
  count                = var.create_azuread_resources && var.create_aks_role_assignments ? 1 : 0
  scope                = var.aks_cluster_id
  role_definition_name = "Azure Kubernetes Service RBAC Reader"
  principal_id         = azuread_group.aks_developers[0].object_id
}

# --- Workload Identity: App Registration for OIDC ---
resource "azuread_application" "workload_app" {
  for_each     = var.create_azuread_resources ? var.workload_identities : {}
  display_name = "wi-${var.environment}-${each.key}"
}

resource "azuread_service_principal" "workload_sp" {
  for_each  = var.create_azuread_resources ? var.workload_identities : {}
  client_id = azuread_application.workload_app[each.key].client_id
}

# Federated credential for Kubernetes service account
# Only create if AKS OIDC issuer URL is provided (breaks circular dependency)
resource "azuread_application_federated_identity_credential" "workload_federated" {
  for_each       = var.create_azuread_resources && var.create_federated_credentials ? var.workload_identities : {}
  application_id = azuread_application.workload_app[each.key].id
  display_name   = "k8s-${each.key}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = var.aks_oidc_issuer_url
  subject        = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
}

# --- GitHub Actions OIDC Federation ---
resource "azuread_application" "github_actions" {
  count        = var.create_azuread_resources && var.configure_github_oidc ? 1 : 0
  display_name = "github-actions-zt-${var.environment}"
}

resource "azuread_service_principal" "github_actions" {
  count     = var.create_azuread_resources && var.configure_github_oidc ? 1 : 0
  client_id = azuread_application.github_actions[0].client_id
}

resource "azuread_application_federated_identity_credential" "github_main" {
  count          = var.create_azuread_resources && var.configure_github_oidc ? 1 : 0
  application_id = azuread_application.github_actions[0].id
  display_name   = "github-main-branch"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
}

resource "azuread_application_federated_identity_credential" "github_pr" {
  count          = var.create_azuread_resources && var.configure_github_oidc ? 1 : 0
  application_id = azuread_application.github_actions[0].id
  display_name   = "github-pull-request"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:pull_request"
}

resource "azurerm_role_assignment" "github_actions_rg" {
  count                = var.create_azuread_resources && var.configure_github_oidc ? 1 : 0
  scope                = var.resource_group_id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions[0].object_id
}
