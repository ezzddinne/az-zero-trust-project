# Staging environment — production-like with cost controls

terraform {
  required_version = ">= 1.6.0"

  # Azure Blob Storage backend
  backend "azurerm" {
    resource_group_name  = "rg-zt-shared"
    storage_account_name = "stztstateyiqfrw"
    container_name       = "tfstate-staging"
    key                  = "terraform.tfstate"
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

locals {
  environment = "staging"
  location    = var.location
  tags = {
    Environment = "staging"
    Project     = "zero-trust"
    ManagedBy   = "terraform"
    CostCenter  = "staging"
  }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "main" {
  name     = "rg-zt-${local.environment}"
  location = local.location
  tags     = local.tags
}

module "monitoring" {
  source = "../../modules/monitoring"

  resource_group_name = azurerm_resource_group.main.name
  resource_group_id   = azurerm_resource_group.main.id
  location            = local.location
  environment         = local.environment
  tags                = local.tags
  retention_days      = 30
  daily_quota_gb      = 2
  monthly_budget      = var.monthly_budget
  alert_emails        = var.alert_emails
}

module "networking" {
  source = "../../modules/networking"

  resource_group_name = azurerm_resource_group.main.name
  location            = local.location
  environment         = local.environment
  tags                = local.tags

  hub_address_space          = "10.10.0.0/16"
  firewall_subnet_prefix     = "10.10.1.0/26"
  bastion_subnet_prefix      = "10.10.2.0/26"
  dns_subnet_prefix          = "10.10.4.0/28"
  aks_spoke_address_space    = "10.11.0.0/16"
  aks_system_subnet_prefix   = "10.11.0.0/24"
  aks_workload_subnet_prefix = "10.11.1.0/24"
  aks_lb_subnet_prefix       = "10.11.2.0/24"
  data_spoke_address_space   = "10.12.0.0/16"
  pe_subnet_prefix           = "10.12.1.0/24"

  # Staging: NSG segmentation (Firewall optional to save cost)
  deploy_firewall = false
  deploy_bastion  = false
}

module "identity" {
  source = "../../modules/identity"

  environment         = local.environment
  resource_group_id   = azurerm_resource_group.main.id
  tags                = local.tags
  aks_cluster_id      = module.aks.aks_id
  aks_oidc_issuer_url = module.aks.aks_oidc_issuer_url

  workload_identities = {
    "sample-api" = {
      namespace       = "workloads"
      service_account = "sa-sample-api"
    }
  }

  configure_github_oidc = var.configure_github_oidc
  github_org            = var.github_org
  github_repo           = var.github_repo
}

module "acr" {
  source = "../../modules/acr"

  resource_group_name        = azurerm_resource_group.main.name
  location                   = local.location
  environment                = local.environment
  tags                       = local.tags
  unique_suffix              = random_string.suffix.result
  acr_sku                    = "Standard"
  pe_subnet_id               = module.networking.pe_subnet_id
  acr_private_dns_zone_id    = module.networking.acr_private_dns_zone_id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
}

module "aks" {
  source = "../../modules/aks"

  resource_group_name    = azurerm_resource_group.main.name
  resource_group_id      = azurerm_resource_group.main.id
  location               = local.location
  environment            = local.environment
  tags                   = local.tags
  kubernetes_version     = "1.32"
  aks_sku_tier           = "Free"
  aks_admin_group_ids    = [module.identity.aks_admin_group_id]
  aks_system_subnet_id   = module.networking.aks_system_subnet_id
  aks_workload_subnet_id = module.networking.aks_workload_subnet_id
  private_dns_zone_id    = module.networking.aks_private_dns_zone_id
  deploy_firewall        = false

  system_node_vm_size   = "Standard_D2s_v3"
  system_node_autoscale = true
  system_node_min       = 1
  system_node_max       = 2

  workload_node_vm_size = "Standard_D4s_v3"
  workload_node_min     = 1
  workload_node_max     = 5
  use_spot_nodes        = false

  deploy_monitoring_pool  = true
  monitoring_node_vm_size = "Standard_D2s_v3"

  acr_id                     = module.acr.acr_id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
}

module "keyvault" {
  source = "../../modules/keyvault"

  resource_group_name             = azurerm_resource_group.main.name
  location                        = local.location
  environment                     = local.environment
  tags                            = local.tags
  unique_suffix                   = random_string.suffix.result
  key_vault_sku                   = "standard"
  pe_subnet_id                    = module.networking.pe_subnet_id
  keyvault_private_dns_zone_id    = module.networking.keyvault_private_dns_zone_id
  log_analytics_workspace_id      = module.monitoring.log_analytics_workspace_id
  workload_identity_principal_ids = module.identity.workload_identity_principal_ids
  create_sample_secrets           = true
}

output "resource_group_name" { value = azurerm_resource_group.main.name }
output "aks_cluster_name" { value = module.aks.aks_name }
output "acr_login_server" { value = module.acr.acr_login_server }
output "key_vault_name" { value = module.keyvault.key_vault_name }
