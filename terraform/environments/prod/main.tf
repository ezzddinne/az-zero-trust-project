# =============================================================
# Production Environment — Professional & Cost-Optimized
# =============================================================
# This environment balances production-grade security features
# with resource efficiency to minimize costs while maintaining:
#   ✓ AKS Standard tier (SLA-backed 99.95% uptime)
#   ✓ Azure Firewall (network security & egress filtering)
#   ✓ Private cluster (no public API endpoint)
#   ✓ Private endpoints (ACR, KeyVault)
#   ✓ Azure CNI + Calico network policies
#   ✓ 2-node system pool (HA, survives single node failure)
#   ✓ No local accounts (API/RBAC only)
#   ✓ 90-day log retention
#   ✓ Cost monitoring & budget alerts
#
# Resource sizing optimized for 4 vCPU quota:
#   - System nodes: 2 × Standard_D2s_v3 (4 vCPU total)
#   - Workload pool: Disabled (use system pool for workloads)
#   - Monitoring pool: Disabled (use system pool for Prometheus/Falco)
# =============================================================

terraform {
  required_version = ">= 1.6.0"

  # Azure Blob Storage backend
  backend "azurerm" {
    resource_group_name  = "rg-zt-shared"
    storage_account_name = "stztstateyiqfrw"
    container_name       = "tfstate-prod"
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
  environment = "prod"
  location    = var.location
  tags = {
    Environment = "prod"
    Project     = "zero-trust"
    ManagedBy   = "terraform"
    CostCenter  = "production"
    Criticality = "high"
  }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Resource group already exists - using data source
data "azurerm_resource_group" "main" {
  name = "rg-zt-${local.environment}"
}

module "monitoring" {
  source = "../../modules/monitoring"

  resource_group_name = data.azurerm_resource_group.main.name
  resource_group_id   = data.azurerm_resource_group.main.id
  location            = local.location
  environment         = local.environment
  tags                = local.tags
  
  log_analytics_sku = "PerGB2018"
  retention_days      = 90   # Production: longer retention for compliance
  daily_quota_gb      = 5    # Cost-optimized: 5 GB/day (vs dev's 1 GB)
  
  monthly_budget      = var.monthly_budget
  alert_emails        = var.alert_emails
}

module "networking" {
  source = "../../modules/networking"

  resource_group_name = data.azurerm_resource_group.main.name
  location            = local.location
  environment         = local.environment
  tags                = local.tags

  hub_address_space          = "10.20.0.0/16"
  firewall_subnet_prefix     = "10.20.1.0/26"
  bastion_subnet_prefix      = "10.20.2.0/26"
  mgmt_subnet_prefix         = "10.20.3.0/27"
  dns_subnet_prefix          = "10.20.4.0/28"
  aks_spoke_address_space    = "10.21.0.0/16"
  aks_system_subnet_prefix   = "10.21.0.0/24"
  aks_workload_subnet_prefix = "10.21.1.0/24"
  aks_lb_subnet_prefix       = "10.21.2.0/24"
  data_spoke_address_space   = "10.22.0.0/16"
  pe_subnet_prefix           = "10.22.1.0/24"

  # Production: Full Azure Firewall for egress filtering, NO Bastion
  deploy_firewall   = true
  deploy_bastion    = false  # Using Tailscale instead
  firewall_sku_tier = "Standard"
}

module "identity" {
  source = "../../modules/identity"

  environment              = local.environment
  resource_group_id        = data.azurerm_resource_group.main.id
  tags                     = local.tags
  create_azuread_resources = true

  # Disable AKS role assignments to avoid circular dependency
  create_aks_role_assignments = false

  # Workload Identity for sample app
  aks_cluster_id      = module.aks.aks_id
  aks_oidc_issuer_url = module.aks.aks_oidc_issuer_url

  workload_identities = {
    "sample-api" = {
      namespace       = "workloads"
      service_account = "sa-sample-api"
    }
  }

  # Enable federated credentials for workload identity
  create_federated_credentials = true

  configure_github_oidc = false
  github_org            = var.github_org
  github_repo           = var.github_repo
}

module "acr" {
  source = "../../modules/acr"

  resource_group_name        = data.azurerm_resource_group.main.name
  location                   = local.location
  environment                = local.environment
  tags                       = local.tags
  unique_suffix              = random_string.suffix.result
  acr_sku                    = "Premium" # Keep existing SKU to avoid migration issues
  pe_subnet_id               = module.networking.pe_subnet_id
  acr_private_dns_zone_id    = module.networking.acr_private_dns_zone_id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  create_private_endpoint    = true  # Production: private access only
}

module "aks" {
  source = "../../modules/aks"

  resource_group_name        = data.azurerm_resource_group.main.name
  resource_group_id          = data.azurerm_resource_group.main.id
  location                   = local.location
  environment                = local.environment
  tags                       = local.tags
  kubernetes_version         = "1.32"
  aks_sku_tier               = "Standard" # Production: SLA-backed (99.95% uptime)
  aks_admin_group_ids        = []         # Skip Azure AD integration for now
  aks_system_subnet_id       = module.networking.aks_system_subnet_id
  aks_workload_subnet_id     = module.networking.aks_workload_subnet_id
  private_dns_zone_id        = module.networking.aks_private_dns_zone_id
  create_dns_role_assignment = true
  deploy_firewall            = true
  
  # Production: Private cluster, no local accounts (enhanced security)
  enable_private_cluster = true
  enable_local_accounts  = false # Production: API/RBAC only, no kubectl bypass
  network_plugin         = "azure"
  network_policy         = "calico"

  # System pool - Small but HA (2 nodes for redundancy)
  system_node_vm_size   = "Standard_D2s_v3"  # 2 vCPU each
  system_node_autoscale = false               # Fixed size for cost predictability
  system_node_count     = 2                   # HA: survives 1 node failure (4 vCPU total)

  # Workload pool - Disabled to fit vCPU quota (workloads run on system pool)
  deploy_workload_pool    = false  # Quota: 4 vCPU limit, all used by system nodes
  workload_node_vm_size   = "Standard_D2s_v3"
  workload_node_min       = 1
  workload_node_max       = 3
  use_spot_nodes          = false  # Production: regular VMs for reliability

  # Monitoring pool - Disabled (monitoring runs on system pool)
  deploy_monitoring_pool  = false
  monitoring_node_vm_size = "Standard_D2s_v3"

  acr_id                     = module.acr.acr_id
  create_acr_pull_assignment = true
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  
  depends_on = [module.networking]
}

module "keyvault" {
  source = "../../modules/keyvault"

  resource_group_name             = data.azurerm_resource_group.main.name
  location                        = local.location
  environment                     = local.environment
  tags                            = local.tags
  unique_suffix                   = random_string.suffix.result
  key_vault_sku                   = "standard" # premium for HSM-backed
  pe_subnet_id                    = module.networking.pe_subnet_id
  keyvault_private_dns_zone_id    = module.networking.keyvault_private_dns_zone_id
  log_analytics_workspace_id      = module.monitoring.log_analytics_workspace_id
  workload_identity_principal_ids = module.identity.workload_identity_principal_ids
  create_sample_secrets           = false
  
  # Allow your IP for Terraform operations
  allowed_ip_addresses = ["102.157.171.54"]
}

module "storage" {
  source = "../../modules/storage"

  resource_group_name         = data.azurerm_resource_group.main.name
  location                    = local.location
  environment                 = local.environment
  tags                        = local.tags
  unique_suffix               = random_string.suffix.result
  replication_type            = "GRS"
  create_private_endpoint     = true
  pe_subnet_id                = module.networking.pe_subnet_id
  storage_private_dns_zone_id = module.networking.storage_private_dns_zone_id
}

# Retrieve Tailscale auth key from Key Vault
data "azurerm_key_vault_secret" "tailscale_authkey" {
  name         = "tailscalekey"
  key_vault_id = module.keyvault.key_vault_id
}

module "tailscale_vm" {
  source = "../../modules/tailscale-vm"

  resource_group_name = data.azurerm_resource_group.main.name
  location            = local.location
  environment         = local.environment
  tags                = local.tags
  subnet_id           = module.networking.mgmt_subnet_id
  vm_size             = "Standard_D2s_v3"  # 2 vCPU, 8 GB RAM (~$70/month)
  key_vault_id        = module.keyvault.key_vault_id
  
  # Tailscale auth key from Key Vault for automatic connection
  tailscale_authkey   = data.azurerm_key_vault_secret.tailscale_authkey.value
  
  # SSH key will be auto-generated and stored in Key Vault
  # Or provide your own: ssh_public_key = var.tailscale_vm_ssh_key
}

output "resource_group_name" { value = data.azurerm_resource_group.main.name }
output "aks_cluster_name" { value = module.aks.aks_name }
output "acr_login_server" { value = module.acr.acr_login_server }
output "key_vault_name" { value = module.keyvault.key_vault_name }
output "tailscale_vm_name" { value = module.tailscale_vm.vm_name }
output "tailscale_vm_private_ip" { value = module.tailscale_vm.private_ip_address }

# Workload Identity outputs
output "workload_identity_client_ids" {
  value       = module.identity.workload_identity_client_ids
  description = "Map of workload identity client IDs"
}

output "workload_identity_principal_ids" {
  value       = module.identity.workload_identity_principal_ids
  description = "Map of workload identity principal IDs"
}
