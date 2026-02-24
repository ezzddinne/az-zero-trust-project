output "aks_id" {
  value = azurerm_kubernetes_cluster.main.id
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "aks_fqdn" {
  value = azurerm_kubernetes_cluster.main.private_fqdn
}

output "aks_oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "aks_kubelet_identity_client_id" {
  value = azurerm_user_assigned_identity.aks_kubelet.client_id
}

output "aks_kubelet_identity_object_id" {
  value = azurerm_user_assigned_identity.aks_kubelet.principal_id
}

output "aks_identity_principal_id" {
  value = azurerm_user_assigned_identity.aks.principal_id
}

output "aks_node_resource_group" {
  value = azurerm_kubernetes_cluster.main.node_resource_group
}
