# -----------------------------------------------------
# Storage Module — Terraform State + General Storage
# Zero Trust: Never Trust (no public access)
# -----------------------------------------------------

resource "azurerm_storage_account" "main" {
  name                = "stzt${var.environment}${var.unique_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location

  account_tier             = "Standard"
  account_replication_type = var.replication_type
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"

  # Zero Trust: No public blob access
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false

  # Encryption at rest
  infrastructure_encryption_enabled = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = var.tags
}

# --- Private Endpoint ---
resource "azurerm_private_endpoint" "storage" {
  count               = var.create_private_endpoint ? 1 : 0
  name                = "pe-st-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id

  private_service_connection {
    name                           = "psc-st-${var.environment}"
    private_connection_resource_id = azurerm_storage_account.main.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "pdz-st-${var.environment}"
    private_dns_zone_ids = [var.storage_private_dns_zone_id]
  }

  tags = var.tags
}
