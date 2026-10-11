# Guardrails on the workload's resource group, using built-in policy definitions.
# In a real landing zone these sit on a management group, not a resource group.

resource "azurerm_resource_group_policy_assignment" "allowed_locations" {
  name                 = "allowed-locations-ch"
  display_name         = "Resources only in Switzerland"
  resource_group_id    = azurerm_resource_group.aks.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
  parameters = jsonencode({
    listOfAllowedLocations = { value = ["switzerlandnorth", "switzerlandwest"] }
    effect                 = { value = "Deny" }
  })
}

# Tags: inherit "project" from the resource group instead of denying untagged resources.
# A Deny policy would also block resources Azure creates for you (e.g. the AKS monitoring
# add-on's data collection rule), breaking things silently. Modify fixes the tag instead.
# Modify policies need an identity: it's used for remediation of resources that already exist.
resource "azurerm_resource_group_policy_assignment" "inherit_project_tag" {
  name                 = "inherit-tag-project"
  display_name         = "Inherit the 'project' tag from the resource group"
  resource_group_id    = azurerm_resource_group.aks.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/ea3f2387-9b95-492a-a190-fcdc54f7b070"
  location             = var.location
  parameters = jsonencode({
    tagName = { value = "project" }
  })

  identity {
    type = "SystemAssigned"
  }
}

# The role the policy definition asks for (Contributor), scoped to this resource group only.
resource "azurerm_role_assignment" "inherit_tag_remediation" {
  scope                = azurerm_resource_group.aks.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_resource_group_policy_assignment.inherit_project_tag.identity[0].principal_id
}

# Audit only: reports clusters that still allow local (non-Entra) admin accounts.
resource "azurerm_resource_group_policy_assignment" "aks_no_local_accounts" {
  name                 = "aks-no-local-accounts"
  display_name         = "AKS clusters should have local accounts disabled (audit)"
  resource_group_id    = azurerm_resource_group.aks.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/993c2fcd-2b29-49d2-9eb0-df2c3a730c32"
  parameters = jsonencode({
    effect = { value = "Audit" }
  })
}
