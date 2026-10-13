output "resource_group" {
  value = azurerm_resource_group.audit.name
}

output "storage_account" {
  value = azurerm_storage_account.audit.name
}

output "container" {
  value = azurerm_storage_container.github_audit.name
}
