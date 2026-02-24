# ============================================================
# Tailscale Access VM Module
# ============================================================
# Creates a lightweight Ubuntu VM with Tailscale for secure
# remote access to private AKS cluster and Azure resources
# ============================================================

# Network Interface for Tailscale VM
resource "azurerm_network_interface" "tailscale" {
  name                = "nic-tailscale-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.tags
}

# Network Security Group for Tailscale VM
resource "azurerm_network_security_group" "tailscale" {
  name                = "nsg-tailscale-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  # Allow Tailscale's DERP and direct connections
  security_rule {
    name                       = "AllowTailscaleUDP"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "41641"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  security_rule {
    name                       = "AllowTailscaleHTTPS"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  # Allow internal VNet communication
  security_rule {
    name                       = "AllowVNetInBound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowVNetOutBound"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
  }

  tags = var.tags
}

# Associate NSG with NIC
resource "azurerm_network_interface_security_group_association" "tailscale" {
  network_interface_id      = azurerm_network_interface.tailscale.id
  network_security_group_id = azurerm_network_security_group.tailscale.id
}

# Tailscale VM
resource "azurerm_linux_virtual_machine" "tailscale" {
  name                = "vm-tailscale-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_size
  admin_username      = var.admin_username

  # SSH authentication with Azure-generated key
  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.tailscale[0].public_key_openssh
  }

  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.tailscale.id
  ]

  os_disk {
    name                 = "osdisk-tailscale-${var.environment}"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  # Cloud-init to install essential tools
  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    tailscale_authkey = var.tailscale_authkey
    environment       = var.environment
  }))

  tags = merge(var.tags, {
    Purpose = "Tailscale-Access-Gateway"
  })

  lifecycle {
    ignore_changes = [
      custom_data # Prevent recreation on cloud-init changes
    ]
  }
}

# Generate SSH key if not provided
resource "tls_private_key" "tailscale" {
  count     = var.ssh_public_key == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Store private key in Key Vault (if generated and Key Vault is provided)
resource "azurerm_key_vault_secret" "tailscale_ssh_private_key" {
  count        = var.ssh_public_key == "" ? 1 : 0
  name         = "tailscale-vm-ssh-private-key-${var.environment}"
  value        = tls_private_key.tailscale[0].private_key_pem
  key_vault_id = var.key_vault_id

  tags = var.tags

  depends_on = [azurerm_linux_virtual_machine.tailscale]
}

# Grant VM's managed identity access to read its own SSH key from Key Vault
resource "azurerm_role_assignment" "tailscale_kv_secrets_reader" {
  count                = var.ssh_public_key == "" ? 1 : 0
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.tailscale.identity[0].principal_id
}
