output "resource_group" {
  value = azurerm_resource_group.aks.name
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.lab.name
}

output "key_vault_name" {
  value = azurerm_key_vault.lab.name
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "lab_api_client_id" {
  description = "Client ID the lab-api service account is annotated with."
  value       = azurerm_user_assigned_identity.lab_api.client_id
}

output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.lab.oidc_issuer_url
}

output "kubeconfig_command" {
  value = "az aks get-credentials -g ${azurerm_resource_group.aks.name} -n ${azurerm_kubernetes_cluster.lab.name} --overwrite-existing && kubelogin convert-kubeconfig -l azurecli"
}
