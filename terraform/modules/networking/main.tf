# -----------------------------------------------------
# Networking Module — Hub-and-Spoke Architecture
# Zero Trust: Never Trust network location, Assume Breach
# -----------------------------------------------------

# --- Hub VNet ---
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.hub_address_space]

  tags = var.tags
}

# Hub Subnets
resource "azurerm_subnet" "firewall" {
  count                = var.deploy_firewall ? 1 : 0
  name                 = "AzureFirewallSubnet" # Required name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.firewall_subnet_prefix]
}

resource "azurerm_subnet" "bastion" {
  count                = var.deploy_bastion ? 1 : 0
  name                 = "AzureBastionSubnet" # Required name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.bastion_subnet_prefix]
}

resource "azurerm_subnet" "mgmt" {
  name                 = "snet-mgmt-${var.environment}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.mgmt_subnet_prefix]
}

resource "azurerm_subnet" "dns_resolver" {
  name                 = "snet-dns-${var.environment}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.dns_subnet_prefix]

  delegation {
    name = "dns-resolver"
    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# --- AKS Spoke VNet ---
resource "azurerm_virtual_network" "aks_spoke" {
  name                = "vnet-aks-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.aks_spoke_address_space]

  tags = var.tags
}

resource "azurerm_subnet" "aks_system" {
  name                 = "snet-aks-system-${var.environment}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.aks_spoke.name
  address_prefixes     = [var.aks_system_subnet_prefix]
}

resource "azurerm_subnet" "aks_workload" {
  name                 = "snet-aks-workload-${var.environment}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.aks_spoke.name
  address_prefixes     = [var.aks_workload_subnet_prefix]
}

resource "azurerm_subnet" "aks_internal_lb" {
  name                 = "snet-aks-lb-${var.environment}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.aks_spoke.name
  address_prefixes     = [var.aks_lb_subnet_prefix]
}

# --- Data Spoke VNet ---
resource "azurerm_virtual_network" "data_spoke" {
  name                = "vnet-data-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.data_spoke_address_space]

  tags = var.tags
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = "snet-pe-${var.environment}"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.data_spoke.name
  address_prefixes                  = [var.pe_subnet_prefix]
  private_endpoint_network_policies = "Disabled" # Required for private endpoints
}

# --- VNet Peering: Hub <-> AKS Spoke ---
resource "azurerm_virtual_network_peering" "hub_to_aks" {
  name                         = "peer-hub-to-aks"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.aks_spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
}

resource "azurerm_virtual_network_peering" "aks_to_hub" {
  name                         = "peer-aks-to-hub"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.aks_spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = false
}

# --- VNet Peering: Hub <-> Data Spoke ---
resource "azurerm_virtual_network_peering" "hub_to_data" {
  name                         = "peer-hub-to-data"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.data_spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
}

resource "azurerm_virtual_network_peering" "data_to_hub" {
  name                         = "peer-data-to-hub"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.data_spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = false
}

# --- VNet Peering: AKS Spoke <-> Data Spoke (for Private Endpoints) ---
resource "azurerm_virtual_network_peering" "aks_to_data" {
  name                         = "peer-aks-to-data"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.aks_spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.data_spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
}

resource "azurerm_virtual_network_peering" "data_to_aks" {
  name                         = "peer-data-to-aks"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.data_spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.aks_spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
}

# --- NSGs (Default Deny) ---
resource "azurerm_network_security_group" "aks_system" {
  name                = "nsg-aks-system-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  # Allow AKS required traffic
  security_rule {
    name                       = "AllowAKSApiServer"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureCloud"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowKubeletFromApiServer"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "10250"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  # Allow all VNet-internal inbound (required for AKS node-to-node, API server
  # private endpoint, pod-to-pod with Azure CNI, and system component communication).
  # Pod-level microsegmentation is enforced by Calico network policies.
  security_rule {
    name                       = "AllowVNetInBound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Allow Azure Load Balancer health probes (required for AKS Standard LB)
  security_rule {
    name                       = "AllowAzureLBInBound"
    priority                   = 210
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # Deny everything else inbound
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow outbound to Azure services (required for AKS nodes to reach API server)
  security_rule {
    name                       = "AllowOutboundHttps"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow outbound HTTP for package downloads
  security_rule {
    name                       = "AllowOutboundHttp"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow outbound NTP for time sync
  security_rule {
    name                       = "AllowNtpOutbound"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "123"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow DNS outbound (critical for private cluster)
  security_rule {
    name                       = "AllowDnsOutbound"
    priority                   = 125
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "53"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow intra-VNet communication (node-to-node, node-to-API server)
  security_rule {
    name                       = "AllowIntraVnet"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Allow tunnel front pod communication (required for private cluster)
  security_rule {
    name                       = "AllowTunnelFrontTcp"
    priority                   = 140
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9000"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud"
  }

  security_rule {
    name                       = "AllowTunnelFrontUdp"
    priority                   = 150
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "1194"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud"
  }

  tags = var.tags
}

resource "azurerm_network_security_group" "aks_workload" {
  name                = "nsg-aks-workload-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "AllowFromSystemPool"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.aks_system_subnet_prefix
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowIntraWorkload"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.aks_workload_subnet_prefix
    destination_address_prefix = "*"
  }

  # Allow all VNet-internal inbound (AKS node communication, Azure CNI pod traffic).
  # Pod-level microsegmentation is enforced by Calico network policies.
  security_rule {
    name                       = "AllowVNetInBound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Allow Azure Load Balancer health probes
  security_rule {
    name                       = "AllowAzureLBInBound"
    priority                   = 210
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # Deny everything else inbound
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow outbound HTTPS
  security_rule {
    name                       = "AllowOutboundHttps"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow outbound HTTP
  security_rule {
    name                       = "AllowOutboundHttp"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow intra-VNet communication (node-to-node, node-to-API server)
  security_rule {
    name                       = "AllowIntraVnet"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Allow DNS outbound (critical for private cluster)
  security_rule {
    name                       = "AllowDnsOutbound"
    priority                   = 125
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "53"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow tunnel front pod communication (required for private cluster)
  security_rule {
    name                       = "AllowTunnelFrontTcp"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9000"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud"
  }

  security_rule {
    name                       = "AllowTunnelFrontUdp"
    priority                   = 140
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "1194"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud"
  }

  # Allow NTP outbound
  security_rule {
    name                       = "AllowNtpOutbound"
    priority                   = 145
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "123"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-pe-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow traffic from AKS spoke only
  security_rule {
    name                       = "AllowFromAKS"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.aks_spoke_address_space
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# --- NSG Associations ---
resource "azurerm_subnet_network_security_group_association" "aks_system" {
  subnet_id                 = azurerm_subnet.aks_system.id
  network_security_group_id = azurerm_network_security_group.aks_system.id
}

resource "azurerm_subnet_network_security_group_association" "aks_workload" {
  subnet_id                 = azurerm_subnet.aks_workload.id
  network_security_group_id = azurerm_network_security_group.aks_workload.id
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

# --- Azure Firewall (Production only) ---
resource "azurerm_public_ip" "firewall" {
  count               = var.deploy_firewall ? 1 : 0
  name                = "pip-fw-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_firewall" "main" {
  count               = var.deploy_firewall ? 1 : 0
  name                = "fw-zt-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = var.firewall_sku_tier

  ip_configuration {
    name                 = "fw-ipconfig"
    subnet_id            = azurerm_subnet.firewall[0].id
    public_ip_address_id = azurerm_public_ip.firewall[0].id
  }

  tags = var.tags
}

# Firewall Network Rule: Allow AKS to Azure services
resource "azurerm_firewall_network_rule_collection" "aks_azure" {
  count               = var.deploy_firewall ? 1 : 0
  name                = "aks-azure-services"
  azure_firewall_name = azurerm_firewall.main[0].name
  resource_group_name = var.resource_group_name
  priority            = 100
  action              = "Allow"

  rule {
    name                  = "aks-to-azure"
    source_addresses      = [var.aks_spoke_address_space]
    destination_ports     = ["443"]
    destination_addresses = ["AzureCloud"]
    protocols             = ["TCP"]
  }

  rule {
    name                  = "aks-ntp"
    source_addresses      = [var.aks_spoke_address_space]
    destination_ports     = ["123"]
    destination_addresses = ["*"]
    protocols             = ["UDP"]
  }

  rule {
    name                  = "aks-dns"
    source_addresses      = [var.aks_spoke_address_space]
    destination_ports     = ["53"]
    destination_addresses = ["*"]
    protocols             = ["UDP", "TCP"]
  }

  rule {
    name                  = "aks-github-ssh"
    source_addresses      = [var.aks_spoke_address_space]
    destination_ports     = ["22"]
    destination_addresses = ["140.82.112.0/20", "140.82.113.0/20", "140.82.114.0/20", "140.82.115.0/20", "140.82.116.0/20", "140.82.117.0/20", "140.82.118.0/20", "140.82.119.0/20", "140.82.120.0/20", "140.82.121.0/20", "140.82.122.0/20", "140.82.123.0/20", "140.82.124.0/20", "140.82.125.0/20", "140.82.126.0/20", "140.82.127.0/20"]
    protocols             = ["TCP"]
  }
}

# Firewall Application Rule: Allow only required FQDNs
resource "azurerm_firewall_application_rule_collection" "aks_fqdn" {
  count               = var.deploy_firewall ? 1 : 0
  name                = "aks-required-fqdn"
  azure_firewall_name = azurerm_firewall.main[0].name
  resource_group_name = var.resource_group_name
  priority            = 200
  action              = "Allow"

  rule {
    name             = "aks-required"
    source_addresses = [var.aks_spoke_address_space]
    fqdn_tags        = ["AzureKubernetesService"]
  }

  rule {
    name             = "container-registries"
    source_addresses = [var.aks_spoke_address_space]
    target_fqdns = [
      "*.azurecr.io",
      "mcr.microsoft.com",
      "*.data.mcr.microsoft.com",
    ]
    protocol {
      type = "Https"
      port = 443
    }
  }

  rule {
    name             = "monitoring"
    source_addresses = [var.aks_spoke_address_space]
    target_fqdns = [
      "dc.services.visualstudio.com",
      "*.monitoring.azure.com",
    ]
    protocol {
      type = "Https"
      port = 443
    }
  }

  rule {
    name             = "ubuntu-packages"
    source_addresses = [var.aks_spoke_address_space]
    target_fqdns = [
      "packages.microsoft.com",
      "azure.archive.ubuntu.com",
      "security.ubuntu.com",
      "archive.ubuntu.com",
      "changelogs.ubuntu.com",
      "snapcraft.io",
      "api.snapcraft.io",
    ]
    protocol {
      type = "Https"
      port = 443
    }
    protocol {
      type = "Http"
      port = 80
    }
  }

  rule {
    name             = "github-releases"
    source_addresses = [var.aks_spoke_address_space]
    target_fqdns = [
      "github.com",
      "*.github.com",
      "ghcr.io",
      "*.ghcr.io",
      "raw.githubusercontent.com",
    ]
    protocol {
      type = "Https"
      port = 443
    }
  }

  rule {
    name             = "azure-storage"
    source_addresses = [var.aks_spoke_address_space]
    target_fqdns = [
      "*.blob.core.windows.net",
      "*.table.core.windows.net",
      "*.queue.core.windows.net",
    ]
    protocol {
      type = "Https"
      port = 443
    }
  }

  rule {
    name             = "microsoft-download"
    source_addresses = [var.aks_spoke_address_space]
    target_fqdns = [
      "download.microsoft.com",
      "*.download.microsoft.com",
      "login.microsoftonline.com",
      "*.login.microsoftonline.com",
    ]
    protocol {
      type = "Https"
      port = 443
    }
  }
}

# --- Route Table for AKS (force egress through Firewall) ---
resource "azurerm_route_table" "aks" {
  count                         = var.deploy_firewall ? 1 : 0
  name                          = "rt-aks-${var.environment}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = false

  route {
    name                   = "default-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.main[0].ip_configuration[0].private_ip_address
  }

  tags = var.tags
}

resource "azurerm_subnet_route_table_association" "aks_system" {
  count          = var.deploy_firewall ? 1 : 0
  subnet_id      = azurerm_subnet.aks_system.id
  route_table_id = azurerm_route_table.aks[0].id
}

resource "azurerm_subnet_route_table_association" "aks_workload" {
  count          = var.deploy_firewall ? 1 : 0
  subnet_id      = azurerm_subnet.aks_workload.id
  route_table_id = azurerm_route_table.aks[0].id
}

# --- Private DNS Zones ---
resource "azurerm_private_dns_zone" "keyvault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "storage_blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# AKS Private Cluster DNS Zone
resource "azurerm_private_dns_zone" "aks" {
  name                = "privatelink.${var.location}.azmk8s.io"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Link Private DNS Zones to Hub VNet (for resolution)
resource "azurerm_private_dns_zone_virtual_network_link" "keyvault_hub" {
  name                  = "link-kv-hub"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr_hub" {
  name                  = "link-acr-hub"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_hub" {
  name                  = "link-storage-hub"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "aks_hub" {
  name                  = "link-aks-hub"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.aks.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
}

# Link to AKS Spoke
resource "azurerm_private_dns_zone_virtual_network_link" "keyvault_aks" {
  name                  = "link-kv-aks"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = azurerm_virtual_network.aks_spoke.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr_aks" {
  name                  = "link-acr-aks"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = azurerm_virtual_network.aks_spoke.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_aks" {
  name                  = "link-storage-aks"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob.name
  virtual_network_id    = azurerm_virtual_network.aks_spoke.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "aks_spoke" {
  name                  = "link-aks-aks"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.aks.name
  virtual_network_id    = azurerm_virtual_network.aks_spoke.id
  registration_enabled  = false
}

# Link to Data Spoke
resource "azurerm_private_dns_zone_virtual_network_link" "keyvault_data" {
  name                  = "link-kv-data"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = azurerm_virtual_network.data_spoke.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr_data" {
  name                  = "link-acr-data"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = azurerm_virtual_network.data_spoke.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_data" {
  name                  = "link-storage-data"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob.name
  virtual_network_id    = azurerm_virtual_network.data_spoke.id
  registration_enabled  = false
}
