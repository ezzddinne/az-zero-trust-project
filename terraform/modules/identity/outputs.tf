output "aks_admin_group_id" {
  value = var.create_azuread_resources ? azuread_group.aks_admins[0].object_id : null
}

output "aks_developer_group_id" {
  value = var.create_azuread_resources ? azuread_group.aks_developers[0].object_id : null
}

output "security_readers_group_id" {
  value = var.create_azuread_resources ? azuread_group.security_readers[0].object_id : null
}

output "workload_identity_client_ids" {
  value = var.create_azuread_resources ? { for k, v in azuread_application.workload_app : k => v.client_id } : {}
}

output "workload_identity_principal_ids" {
  value = var.create_azuread_resources ? { for k, v in azuread_service_principal.workload_sp : k => v.object_id } : {}
}

output "github_actions_client_id" {
  value = var.create_azuread_resources && var.configure_github_oidc ? azuread_application.github_actions[0].client_id : null
}
