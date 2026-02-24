# ┌─────────────────────────────────────────────────────────────────┐
# │  Azure Policy Definitions — Zero Trust Enforcement              │
# │  These custom policies enforce ZT controls at the Azure plane   │
# └─────────────────────────────────────────────────────────────────┘
#
# Deploy via:  az policy definition create --name <name> --rules <file> --params <file>
# Assign via:  az policy assignment create --policy <id> --scope <rg-id>

# ──────────────────────────────────────────────────────────────────
# 1. Deny public IP creation inside AKS spoke resource group
# ──────────────────────────────────────────────────────────────────
resource "azurerm_policy_definition" "deny_public_ip" {
  name         = "zt-deny-public-ip"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Zero Trust — Deny Public IP Addresses"
  description  = "Prevents creation of public IP addresses to enforce private-only networking."

  metadata = jsonencode({
    category = "Zero Trust - Network"
    version  = "1.0.0"
  })

  policy_rule = jsonencode({
    if = {
      field  = "type"
      equals = "Microsoft.Network/publicIPAddresses"
    }
    then = {
      effect = "Deny"
    }
  })
}

# ──────────────────────────────────────────────────────────────────
# 2. Enforce HTTPS-only on Storage Accounts
# ──────────────────────────────────────────────────────────────────
resource "azurerm_policy_definition" "enforce_https_storage" {
  name         = "zt-enforce-https-storage"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Zero Trust — Enforce HTTPS on Storage"
  description  = "Ensures all storage accounts require HTTPS traffic only."

  metadata = jsonencode({
    category = "Zero Trust - Data"
    version  = "1.0.0"
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.Storage/storageAccounts"
        },
        {
          field    = "Microsoft.Storage/storageAccounts/supportsHttpsTrafficOnly"
          notEquals = "true"
        }
      ]
    }
    then = {
      effect = "Deny"
    }
  })
}

# ──────────────────────────────────────────────────────────────────
# 3. Enforce private endpoint on Key Vault
# ──────────────────────────────────────────────────────────────────
resource "azurerm_policy_definition" "keyvault_private_endpoint" {
  name         = "zt-keyvault-private-endpoint"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Zero Trust — Key Vault Must Use Private Endpoint"
  description  = "Audit Key Vaults that do not have a private endpoint connection."

  metadata = jsonencode({
    category = "Zero Trust - Secrets"
    version  = "1.0.0"
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.KeyVault/vaults"
        },
        {
          field  = "Microsoft.KeyVault/vaults/networkAcls.defaultAction"
          equals = "Allow"
        }
      ]
    }
    then = {
      effect = "Audit"
    }
  })
}

# ──────────────────────────────────────────────────────────────────
# 4. Enforce minimum TLS version on AKS
# ──────────────────────────────────────────────────────────────────
resource "azurerm_policy_definition" "aks_private_cluster" {
  name         = "zt-aks-private-cluster"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Zero Trust — AKS Must Be Private Cluster"
  description  = "Denies AKS clusters that do not have private cluster enabled."

  metadata = jsonencode({
    category = "Zero Trust - Workload"
    version  = "1.0.0"
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.ContainerService/managedClusters"
        },
        {
          field    = "Microsoft.ContainerService/managedClusters/apiServerAccessProfile.enablePrivateCluster"
          notEquals = true
        }
      ]
    }
    then = {
      effect = "Deny"
    }
  })
}

# ──────────────────────────────────────────────────────────────────
# 5. Enforce ACR admin account disabled
# ──────────────────────────────────────────────────────────────────
resource "azurerm_policy_definition" "acr_no_admin" {
  name         = "zt-acr-no-admin"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Zero Trust — ACR Admin Account Disabled"
  description  = "Denies container registries with admin account enabled."

  metadata = jsonencode({
    category = "Zero Trust - Supply Chain"
    version  = "1.0.0"
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.ContainerRegistry/registries"
        },
        {
          field  = "Microsoft.ContainerRegistry/registries/adminUserEnabled"
          equals = "true"
        }
      ]
    }
    then = {
      effect = "Deny"
    }
  })
}

# ──────────────────────────────────────────────────────────────────
# Policy Initiative (Assignment Group)
# ──────────────────────────────────────────────────────────────────
resource "azurerm_policy_set_definition" "zero_trust_initiative" {
  name         = "zt-initiative"
  policy_type  = "Custom"
  display_name = "Zero Trust Security Initiative"
  description  = "Collection of policies enforcing Zero Trust principles across Azure resources."

  metadata = jsonencode({
    category = "Zero Trust"
    version  = "1.0.0"
  })

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.deny_public_ip.id
    reference_id         = "denyPublicIP"
  }

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.enforce_https_storage.id
    reference_id         = "enforceHTTPSStorage"
  }

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.keyvault_private_endpoint.id
    reference_id         = "kvPrivateEndpoint"
  }

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.aks_private_cluster.id
    reference_id         = "aksPrivateCluster"
  }

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.acr_no_admin.id
    reference_id         = "acrNoAdmin"
  }
}
