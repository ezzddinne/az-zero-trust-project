# -----------------------------------------------------
# AKS Module — Private, Hardened Kubernetes Cluster
# Zero Trust: Never Trust, Least Privilege, Assume Breach
# -----------------------------------------------------

resource "azurerm_user_assigned_identity" "aks" {
  name                = "id-aks-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "aks_kubelet" {
  name                = "id-aks-kubelet-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# AKS cluster identity needs Network Contributor on AKS subnet
resource "azurerm_role_assignment" "aks_network" {
  scope                = var.aks_system_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_role_assignment" "aks_network_workload" {
  scope                = var.aks_workload_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# Kubelet identity needs AcrPull on ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  count                = var.create_acr_pull_assignment ? 1 : 0
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.aks_kubelet.principal_id
}

# AKS control plane needs Managed Identity Operator on kubelet identity
resource "azurerm_role_assignment" "aks_kubelet_operator" {
  scope                = azurerm_user_assigned_identity.aks_kubelet.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# AKS identity needs Private DNS Zone Contributor for private cluster with custom DNS zone
resource "azurerm_role_assignment" "aks_dns_contributor" {
  count                = var.create_dns_role_assignment ? 1 : 0
  scope                = var.private_dns_zone_id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# --- AKS Cluster ---
resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-zt-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "aks-zt-${var.environment}"
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.aks_sku_tier

  # Private cluster configuration (optional for dev)
  private_cluster_enabled             = var.enable_private_cluster
  private_cluster_public_fqdn_enabled = false
  private_dns_zone_id                 = var.enable_private_cluster ? var.private_dns_zone_id : null

  # Local accounts (enabled for dev, disabled for prod)
  local_account_disabled = !var.enable_local_accounts

  # Identity: User-assigned Managed Identity (no service principal)
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.aks_kubelet.client_id
    object_id                 = azurerm_user_assigned_identity.aks_kubelet.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.aks_kubelet.id
  }

  # Azure AD Integration (Entra ID)
  azure_active_directory_role_based_access_control {
    managed                = true  # Azure-managed AAD integration
    azure_rbac_enabled     = false # Use Kubernetes RBAC for portability
    admin_group_object_ids = var.aks_admin_group_ids
  }

  # Networking: Azure CNI + Calico for Zero Trust
  network_profile {
    network_plugin    = var.network_plugin
    network_policy    = var.network_policy
    load_balancer_sku = "standard"
    outbound_type     = var.deploy_firewall ? "userDefinedRouting" : "loadBalancer"
    service_cidr      = "172.16.0.0/16"
    dns_service_ip    = "172.16.0.10"
  }

  # System Node Pool
  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_node_vm_size
    os_disk_size_gb              = 50
    os_disk_type                 = "Managed"
    vnet_subnet_id               = var.aks_system_subnet_id
    enable_auto_scaling          = var.system_node_autoscale
    min_count                    = var.system_node_autoscale ? var.system_node_min : null
    max_count                    = var.system_node_autoscale ? var.system_node_max : null
    node_count                   = var.system_node_autoscale ? null : var.system_node_count
    only_critical_addons_enabled = true
    temporary_name_for_rotation  = "systemtemp"

    node_labels = {
      "nodepool" = "system"
    }

    upgrade_settings {
      max_surge = "33%"
    }
  }

  # Workload Identity
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Secrets Store CSI Driver
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  # Auto-upgrade for security patches
  automatic_channel_upgrade = "patch"

  # Maintenance window
  maintenance_window {
    allowed {
      day   = "Sunday"
      hours = [2, 3, 4]
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count,
    ]
  }

  depends_on = [
    azurerm_role_assignment.aks_kubelet_operator,
    azurerm_role_assignment.aks_network,
    azurerm_role_assignment.aks_network_workload
  ]
}

# --- Workload Node Pool ---
resource "azurerm_kubernetes_cluster_node_pool" "workload" {
  count                 = var.deploy_workload_pool ? 1 : 0
  name                  = "workload"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.workload_node_vm_size
  os_disk_size_gb       = 50
  os_disk_type          = "Managed"
  vnet_subnet_id        = var.aks_workload_subnet_id
  enable_auto_scaling   = true
  min_count             = var.workload_node_min
  max_count             = var.workload_node_max
  priority              = var.use_spot_nodes ? "Spot" : "Regular"
  eviction_policy       = var.use_spot_nodes ? "Delete" : null
  spot_max_price        = var.use_spot_nodes ? -1 : null

  node_labels = {
    "nodepool"             = "workload"
    "workload/priority"    = var.use_spot_nodes ? "spot" : "regular"
  }

  node_taints = var.use_spot_nodes ? ["workload/priority=spot:NoSchedule"] : []

  # Spot instances don't support max surge
  dynamic "upgrade_settings" {
    for_each = var.use_spot_nodes ? [] : [1]
    content {
      max_surge = "33%"
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      node_count,
    ]
  }
}

# --- Monitoring Node Pool (for Prometheus/Grafana/Falco) ---
resource "azurerm_kubernetes_cluster_node_pool" "monitoring" {
  count                 = var.deploy_monitoring_pool ? 1 : 0
  name                  = "monitoring"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.monitoring_node_vm_size
  os_disk_size_gb       = 50
  vnet_subnet_id        = var.aks_workload_subnet_id
  enable_auto_scaling   = false
  node_count            = 1

  node_labels = {
    "nodepool" = "monitoring"
  }

  node_taints = ["workload=monitoring:NoSchedule"]

  tags = var.tags
}

# --- Diagnostic Settings ---
resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "diag-aks-${var.environment}"
  target_resource_id         = azurerm_kubernetes_cluster.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "kube-apiserver"
  }

  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "kube-controller-manager"
  }

  enabled_log {
    category = "guard"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
