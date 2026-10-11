# Lab landing zone: one resource group per workload, network, logging, guardrails, secrets, AKS.
# Everything here is created and destroyed together. Terraform state and the budget live
# separately in rg-platform-lab (scripts/azure-bootstrap.sh) and are never destroyed by this.

data "azurerm_client_config" "current" {}

locals {
  name   = "platformlab"
  suffix = substr(sha1(data.azurerm_client_config.current.subscription_id), 0, 6) # globally unique names
  tags = {
    project     = "platform-lab"
    environment = "lab"
    owner       = "platform-team"
    managed-by  = "terraform"
  }
}

resource "azurerm_resource_group" "aks" {
  name     = "rg-${local.name}-aks"
  location = var.location
  tags     = local.tags
}

# ---------- Network ----------

resource "azurerm_virtual_network" "lab" {
  name                = "vnet-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.aks.name
  address_space       = ["10.40.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "aks_nodes" {
  name                 = "snet-aks-nodes"
  resource_group_name  = azurerm_resource_group.aks.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.40.0.0/22"] # nodes only: pods get overlay IPs, not VNet IPs
}

# ---------- Logging ----------

resource "azurerm_log_analytics_workspace" "lab" {
  name                = "log-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.aks.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 0.5 # cost cap for the lab
  tags                = local.tags
}

# ---------- Secrets ----------

resource "azurerm_key_vault" "lab" {
  name                       = "kv-${local.name}-${local.suffix}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.aks.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true  # Azure RBAC, not legacy access policies
  purge_protection_enabled   = false # lab only; production: true
  soft_delete_retention_days = 7
  tags                       = local.tags
}

# You (whoever runs Terraform) may manage secrets; the app only reads one (identity.tf).
resource "azurerm_role_assignment" "me_kv_secrets_officer" {
  scope                = azurerm_key_vault.lab.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# RBAC changes take a minute to reach Key Vault's data plane.
resource "time_sleep" "kv_rbac" {
  depends_on      = [azurerm_role_assignment.me_kv_secrets_officer]
  create_duration = "60s"
}

resource "azurerm_key_vault_secret" "greeting" {
  name         = "lab-api-greeting"
  value        = "Hello from Azure Key Vault, delivered by workload identity"
  key_vault_id = azurerm_key_vault.lab.id
  depends_on   = [time_sleep.kv_rbac]
}
