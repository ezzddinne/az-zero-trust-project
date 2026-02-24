output "vm_id" {
  description = "Tailscale VM resource ID"
  value       = azurerm_linux_virtual_machine.tailscale.id
}

output "vm_name" {
  description = "Tailscale VM name"
  value       = azurerm_linux_virtual_machine.tailscale.name
}

output "private_ip_address" {
  description = "Private IP address of Tailscale VM"
  value       = azurerm_network_interface.tailscale.private_ip_address
}

output "vm_identity_principal_id" {
  description = "System-assigned managed identity principal ID"
  value       = azurerm_linux_virtual_machine.tailscale.identity[0].principal_id
}

output "ssh_private_key_secret_name" {
  description = "Name of the Key Vault secret containing SSH private key (if generated)"
  value       = var.ssh_public_key == "" ? try(azurerm_key_vault_secret.tailscale_ssh_private_key[0].name, null) : null
}
