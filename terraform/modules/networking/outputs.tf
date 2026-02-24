# VNet IDs
output "hub_vnet_id" {
  value = azurerm_virtual_network.hub.id
}

output "aks_spoke_vnet_id" {
  value = azurerm_virtual_network.aks_spoke.id
}

output "data_spoke_vnet_id" {
  value = azurerm_virtual_network.data_spoke.id
}

# Subnet IDs
output "aks_system_subnet_id" {
  value = azurerm_subnet.aks_system.id

  # Ensure NSG associations are complete before AKS uses these subnets
  depends_on = [
    azurerm_subnet_network_security_group_association.aks_system,
  ]
}

output "aks_workload_subnet_id" {
  value = azurerm_subnet.aks_workload.id

  depends_on = [
    azurerm_subnet_network_security_group_association.aks_workload,
  ]
}

output "aks_lb_subnet_id" {
  value = azurerm_subnet.aks_internal_lb.id
}

output "pe_subnet_id" {
  value = azurerm_subnet.private_endpoints.id
}

output "mgmt_subnet_id" {
  description = "Management subnet ID for Tailscale/jumpbox VMs"
  value       = azurerm_subnet.mgmt.id
}

# Private DNS Zone IDs
output "keyvault_private_dns_zone_id" {
  value = azurerm_private_dns_zone.keyvault.id
}

output "acr_private_dns_zone_id" {
  value = azurerm_private_dns_zone.acr.id
}

output "storage_private_dns_zone_id" {
  value = azurerm_private_dns_zone.storage_blob.id
}

output "aks_private_dns_zone_id" {
  value = azurerm_private_dns_zone.aks.id

  # Critical: AKS private cluster needs DNS VNet links to be active
  # BEFORE the cluster is created, otherwise nodes can't resolve the API server.
  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.aks_hub,
    azurerm_private_dns_zone_virtual_network_link.aks_spoke,
  ]
}

# Firewall
output "firewall_private_ip" {
  value = var.deploy_firewall ? azurerm_firewall.main[0].ip_configuration[0].private_ip_address : null
}
