# Control-plane identity: created first so it can be given rights on the subnet before the
# cluster exists (needed when AKS uses your own VNet).
resource "azurerm_user_assigned_identity" "aks" {
  name                = "id-aks-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.aks.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "aks_subnet" {
  scope                = azurerm_subnet.aks_nodes.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_kubernetes_cluster" "lab" {
  name                = "aks-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.aks.name
  node_resource_group = "rg-${local.name}-aks-nodes"
  dns_prefix          = "aks-${local.name}"
  sku_tier            = "Free" # no uptime SLA; production: Standard

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  # Identity: Entra ID for people, Azure RBAC for authorization, no local admin account.
  local_account_disabled = true
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }

  # API server reachable only from your IP. AKS adds the cluster's own outbound IP automatically.
  # Production: a private cluster, reached through a VPN/jump host or a self-hosted runner.
  api_server_access_profile {
    authorized_ip_ranges = ["${var.admin_ip}/32"]
  }

  # Workload identity: pods get Entra tokens via OIDC federation instead of stored secrets.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  # azurerm 5.x requires this block. Manual = the node pools defined here; Auto = Node
  # Auto-Provisioning (Karpenter-based), which picks VM sizes itself.
  node_provisioning_profile {
    mode = "Manual"
  }

  default_node_pool {
    name                        = "system"
    vm_size                     = var.node_vm_size
    node_count                  = var.node_count
    vnet_subnet_id              = azurerm_subnet.aks_nodes.id
    os_sku                      = "AzureLinux"
    os_disk_size_gb             = 64
    temporary_name_for_rotation = "systemtmp"
    upgrade_settings {
      max_surge = "1"
    }
    tags = local.tags
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay" # pods use 10.244.0.0/16, not VNet addresses
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
    load_balancer_sku   = "standard"
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.lab.id
    msi_auth_for_monitoring_enabled = true
  }

  tags = local.tags

  depends_on = [azurerm_role_assignment.aks_subnet]
}

# You administer the cluster through Azure RBAC (kubectl logs in with Entra ID via kubelogin).
resource "azurerm_role_assignment" "me_aks_admin" {
  scope                = azurerm_kubernetes_cluster.lab.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Needed to fetch the kubeconfig at all (az aks get-credentials).
resource "azurerm_role_assignment" "me_aks_user" {
  scope                = azurerm_kubernetes_cluster.lab.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = data.azurerm_client_config.current.object_id
}
