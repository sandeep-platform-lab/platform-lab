# Workload identity for lab-api: the pod's Kubernetes service account (lab/lab-api) is trusted by
# this Entra identity through a federated credential. No client secret exists anywhere.

resource "azurerm_user_assigned_identity" "lab_api" {
  name                = "id-lab-api"
  location            = var.location
  resource_group_name = azurerm_resource_group.aks.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "lab_api" {
  name                      = "aks-lab-lab-api"
  user_assigned_identity_id = azurerm_user_assigned_identity.lab_api.id
  issuer                    = azurerm_kubernetes_cluster.lab.oidc_issuer_url
  subject                   = "system:serviceaccount:lab:lab-api"
  audience                  = ["api://AzureADTokenExchange"]
}

# Least privilege: read secrets in this vault, nothing else.
resource "azurerm_role_assignment" "lab_api_kv_reader" {
  scope                = azurerm_key_vault.lab.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.lab_api.principal_id
}
