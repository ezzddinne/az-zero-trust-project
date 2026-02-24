# -----------------------------------------------------
# ACR Module — Private Container Registry
# Zero Trust: Verify Explicitly (image provenance)
# -----------------------------------------------------

resource "azurerm_container_registry" "main" {
  name                = "acrzt${var.environment}${var.unique_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.acr_sku

  # Zero Trust: No public access (only for Premium SKU)
  public_network_access_enabled = var.acr_sku == "Premium" ? false : true

  # No admin account (use Managed Identity for pull)
  admin_enabled = false

  # Content trust (image signing validation) - Premium only
  trust_policy {
    enabled = var.acr_sku == "Premium"
  }

  # Retention policy - Premium only, but must exist with enabled=false when downgrading
  retention_policy {
    enabled = var.acr_sku == "Premium"
    days    = var.acr_sku == "Premium" ? 7 : 0
  }

  # Network rules (only for Premium SKU)
  dynamic "network_rule_set" {
    for_each = var.acr_sku == "Premium" ? [1] : []
    content {
      default_action = "Deny"
    }
  }

  tags = var.tags
}

# --- Private Endpoint ---
resource "azurerm_private_endpoint" "acr" {
  count               = var.create_private_endpoint ? 1 : 0
  name                = "pe-acr-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id

  private_service_connection {
    name                           = "psc-acr-${var.environment}"
    private_connection_resource_id = azurerm_container_registry.main.id
    is_manual_connection           = false
    subresource_names              = ["registry"]
  }

  private_dns_zone_group {
    name                 = "pdz-acr-${var.environment}"
    private_dns_zone_ids = [var.acr_private_dns_zone_id]
  }

  tags = var.tags
}

# --- Diagnostic Settings ---
resource "azurerm_monitor_diagnostic_setting" "acr" {
  name                       = "diag-acr-${var.environment}"
  target_resource_id         = azurerm_container_registry.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }

  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
