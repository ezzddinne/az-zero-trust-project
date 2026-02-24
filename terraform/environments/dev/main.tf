# =============================================================
# Dev Environment — Cost-Optimized, Security-Complete
# =============================================================
# This environment demonstrates all Zero Trust controls
# while aggressively minimizing costs for development.
#  =============================================================

terraform {
  required_version = ">= 1.6.0"

  # Azure Blob Storage backend
  backend "azurerm" {
    resource_group_name  = "rg-zt-shared"
    storage_account_name = "stztstateyiqfrw"
    container_name       = "tfstate-dev"
    key                  = "dev.terraform.tfstate"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "azuread" {}

# --- Locals ---
locals {
  environment = "dev"
  location    = var.location
  tags = {
    Environment = "dev"
    Project     = "zero-trust"
    ManagedBy   = "terraform"
    CostCenter  = "development"
  }
}

# --- Random suffix for globally unique names ---
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# --- Resource Group ---
resource "azurerm_resource_group" "main" {
  name     = "rg-zt-${local.environment}"
  location = local.location
  tags     = local.tags
}


# --- Monitoring (deploy first — other modules depend on LAW) ---
module "monitoring" {
  source = "../../modules/monitoring"

  resource_group_name = azurerm_resource_group.main.name
  resource_group_id   = azurerm_resource_group.main.id
  location            = local.location
  environment         = local.environment
  tags                = local.tags

  log_analytics_sku = "PerGB2018"
  retention_days    = 30
  daily_quota_gb    = 1 # Cost control: 1 GB/day max

  monthly_budget = var.monthly_budget
  alert_emails   = var.alert_emails
}

# --- Networking ---
module "networking" {
  source = "../../modules/networking"

  resource_group_name = azurerm_resource_group.main.name
  location            = local.location
  environment         = local.environment
  tags                = local.tags

  # Hub VNet
  hub_address_space      = "10.0.0.0/16"
  firewall_subnet_prefix = "10.0.1.0/26"
  bastion_subnet_prefix  = "10.0.2.0/26"
  dns_subnet_prefix      = "10.0.4.0/28"

  # AKS Spoke
  aks_spoke_address_space    = "10.1.0.0/16"
  aks_system_subnet_prefix   = "10.1.0.0/24"
  aks_workload_subnet_prefix = "10.1.1.0/24"
  aks_lb_subnet_prefix       = "10.1.2.0/24"

  # Data Spoke
  data_spoke_address_space = "10.2.0.0/16"
  pe_subnet_prefix         = "10.2.1.0/24"

  # Cost: No Firewall or Bastion in dev (NSGs provide segmentation)
  deploy_firewall = false
  deploy_bastion  = false
}

# --- Identity & RBAC ---
module "identity" {
  source = "../../modules/identity"

  environment       = local.environment
  resource_group_id = azurerm_resource_group.main.id
  tags              = local.tags

  aks_cluster_id      = module.aks.aks_id
  aks_oidc_issuer_url = module.aks.aks_oidc_issuer_url

  # Workload Identity for sample app
  workload_identities = {
    "sample-api" = {
      namespace       = "workloads"
      service_account = "sa-sample-api"
    }
  }

  # GitHub OIDC
  configure_github_oidc = var.configure_github_oidc
  github_org            = var.github_org
  github_repo           = var.github_repo

  # Skip Azure AD resources - requires Microsoft Graph permissions
  create_azuread_resources = false
}

# --- ACR ---
module "acr" {
  source = "../../modules/acr"

  resource_group_name = azurerm_resource_group.main.name
  location            = local.location
  environment         = local.environment
  tags                = local.tags
  unique_suffix       = random_string.suffix.result

  acr_sku                    = "Basic" # Cost: Basic for dev
  pe_subnet_id               = module.networking.pe_subnet_id
  acr_private_dns_zone_id    = module.networking.acr_private_dns_zone_id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  create_private_endpoint    = false # Private endpoints require Premium SKU
}

# --- AKS ---
module "aks" {
  source = "../../modules/aks"

  resource_group_name = azurerm_resource_group.main.name
  resource_group_id   = azurerm_resource_group.main.id
  location            = local.location
  environment         = local.environment
  tags                = local.tags

  kubernetes_version = "1.32"
  aks_sku_tier       = "Free" # Cost: Free tier for dev

  aks_admin_group_ids = module.identity.aks_admin_group_id != null ? [module.identity.aks_admin_group_id] : []

  # Networking
  aks_system_subnet_id   = module.networking.aks_system_subnet_id
  aks_workload_subnet_id = module.networking.aks_workload_subnet_id
  private_dns_zone_id    = module.networking.aks_private_dns_zone_id
  deploy_firewall        = false

  # Zero Trust: Private cluster with local accounts enabled for dev debugging
  enable_private_cluster = true
  enable_local_accounts  = true       # Allow kubectl access for dev debugging
  network_plugin         = "azure"    # Azure CNI for consistency with prod
  network_policy         = "calico"   # Network policies for microsegmentation

  # System pool — minimal for dev
  system_node_vm_size   = "Standard_D2s_v3"
  system_node_autoscale = false
  system_node_count     = 1

  # Workload pool — spot VMs for cost savings
  workload_node_vm_size = "Standard_D2s_v3"
  workload_node_min     = 1
  workload_node_max     = 3
  use_spot_nodes        = true # Cost: ~60% savings

  # Monitoring pool — not needed in dev
  deploy_monitoring_pool = false

  acr_id                     = module.acr.acr_id
  create_acr_pull_assignment = true
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id

  # Ensure Private DNS Zone VNet links are ready before AKS creates nodes.
  # Without this, nodes fail to resolve the API server private FQDN during bootstrap
  # (VMExtensionError_K8SAPIServerConnFail).
  depends_on = [module.networking]
}

# --- Key Vault ---
module "keyvault" {
  source = "../../modules/keyvault"

  resource_group_name = azurerm_resource_group.main.name
  location            = local.location
  environment         = local.environment
  tags                = local.tags
  unique_suffix       = random_string.suffix.result

  key_vault_sku                   = "standard"
  pe_subnet_id                    = module.networking.pe_subnet_id
  keyvault_private_dns_zone_id    = module.networking.keyvault_private_dns_zone_id
  log_analytics_workspace_id      = module.monitoring.log_analytics_workspace_id
  workload_identity_principal_ids = module.identity.workload_identity_principal_ids
  create_sample_secrets           = false             # Disabled - cannot access KV from GitHub Actions IP
  allowed_ip_addresses            = ["4.227.173.115"] # GitHub Actions runner IP (temporary)
}

# --- Outputs ---
output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  value = module.aks.aks_name
}

output "acr_login_server" {
  value = module.acr.acr_login_server
}

output "key_vault_name" {
  value = module.keyvault.key_vault_name
}

output "github_actions_client_id" {
  value     = module.identity.github_actions_client_id
  sensitive = true
}