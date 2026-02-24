# -----------------------------------------------------
# Key Vault Module — Secrets Management with Private Access
# Zero Trust: Never Trust, Least Privilege
# -----------------------------------------------------

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                = "kv-zt-${var.environment}-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name = var.key_vault_sku

  # Zero Trust: RBAC-based access (no access policies)
  enable_rbac_authorization = true

  # Zero Trust: No public network access (enable temporarily for CI/CD bootstrap)
  # TODO: Set to false after initial deployment when using only Private Endpoints
  # For full Zero Trust compliance, disable this once Workload Identity + PE are operational
  public_network_access_enabled = true

  # Assume Breach: Protect against accidental/malicious deletion
  soft_delete_retention_days = 90
  purge_protection_enabled   = true

  # Network: Allow AzureServices and specified IPs
  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
    ip_rules       = var.allowed_ip_addresses
  }

  tags = var.tags
}

# --- Private Endpoint ---
resource "azurerm_private_endpoint" "keyvault" {
  name                = "pe-kv-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id

  private_service_connection {
    name                           = "psc-kv-${var.environment}"
    private_connection_resource_id = azurerm_key_vault.main.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "pdz-kv-${var.environment}"
    private_dns_zone_ids = [var.keyvault_private_dns_zone_id]
  }

  tags = var.tags
}

# --- RBAC: Grant current deployer Key Vault Administrator (for initial setup) ---
resource "azurerm_role_assignment" "deployer_kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# --- RBAC: AKS Workload Identity gets Secrets User ---
resource "azurerm_role_assignment" "workload_kv_secrets" {
  for_each             = var.workload_identity_principal_ids
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value
}

# --- Diagnostic Settings ---
resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  name                       = "diag-kv-${var.environment}"
  target_resource_id         = azurerm_key_vault.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# --- Sample Secrets (for testing) ---
resource "azurerm_key_vault_secret" "sample_db_connection" {
  count        = var.create_sample_secrets ? 1 : 0
  name         = "db-connection-string"
  value        = "Server=tcp:db-server.database.windows.net;Database=appdb;Authentication=Active Directory Managed Identity;"
  key_vault_id = azurerm_key_vault.main.id

  content_type    = "text/plain"
  expiration_date = timeadd(timestamp(), "720h") # 30 days

  depends_on = [azurerm_role_assignment.deployer_kv_admin]

  lifecycle {
    ignore_changes = [expiration_date]
  }
}

resource "azurerm_key_vault_secret" "sample_api_key" {
  count        = var.create_sample_secrets ? 1 : 0
  name         = "api-key"
  value        = "REPLACE_WITH_ACTUAL_KEY"
  key_vault_id = azurerm_key_vault.main.id

  content_type    = "text/plain"
  expiration_date = timeadd(timestamp(), "720h")

  depends_on = [azurerm_role_assignment.deployer_kv_admin]

  lifecycle {
    ignore_changes = [expiration_date, value]
  }
}
