# Long-lived audit storage for the GitHub Enterprise audit log stream. Separate from
# terraform/azure on purpose: audit evidence must outlive the environments it describes.

data "azurerm_client_config" "current" {}

locals {
  suffix = substr(sha1(data.azurerm_client_config.current.subscription_id), 0, 6)
  tags = {
    project     = "platform-lab"
    environment = "lab"
    owner       = "platform-team"
    managed-by  = "terraform"
    data-class  = "audit"
  }
}

resource "azurerm_resource_group" "audit" {
  name     = "rg-platform-lab-audit"
  location = var.location
  tags     = local.tags
}

# GitHub's Azure Blob streaming authenticates with a SAS URL, which needs shared-key signing on this
# account. Mitigations: the SAS is tied to a stored access policy (revocable, create/write only, on
# one container), an account-wide SAS expiry policy, and a WORM container GitHub can't overwrite.
# Network: GitHub streams from the internet, so a default-deny firewall would block it.
#trivy:ignore:AVD-AZU-0012 GitHub audit log streaming connects from GitHub's public egress; see comment above
resource "azurerm_storage_account" "audit" {
  name                            = "stlabaudit${local.suffix}"
  resource_group_name             = azurerm_resource_group.audit.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS" # zone-redundant: audit data survives a zone failure
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  default_to_oauth_authentication = true # people use Entra ID in the portal and CLI

  sas_policy {
    expiration_period = "31.00:00:00" # flag SAS tokens valid for more than a month
    expiration_action = "Log"
  }

  blob_properties {
    delete_retention_policy {
      days = 14
    }
    container_delete_retention_policy {
      days = 14
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "github_audit" {
  name                  = "github-audit"
  storage_account_id    = azurerm_storage_account.audit.id
  container_access_type = "private"
}

# WORM: for 30 days after each blob is written, nobody (including you) can modify or delete it.
# locked = false so the lab can be torn down; production: locked, and a regulator-driven period.
# GitHub's "Check endpoint" overwrites a blob named _check, which WORM forbids, so the policy is
# switched off (worm_enabled = false) while the stream is set up, then on again. Real audit files
# have unique names and are never overwritten. With a LOCKED policy you couldn't switch it off:
# production would use version-level immutability, where an overwrite creates a new version.
resource "azurerm_storage_container_immutability_policy" "github_audit" {
  count                                 = var.worm_enabled ? 1 : 0
  storage_container_resource_manager_id = azurerm_storage_container.github_audit.id
  immutability_period_in_days           = 30
  locked                                = false
}

# Retention: cool after 30 days, delete after 180 (lab). Banks typically keep audit logs for years.
resource "azurerm_storage_management_policy" "audit" {
  storage_account_id = azurerm_storage_account.audit.id

  rule {
    name    = "github-audit-retention"
    enabled = true
    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["${azurerm_storage_container.github_audit.name}/"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_creation_greater_than = 30
        delete_after_days_since_creation_greater_than       = 180
      }
    }
  }
}

# You read the logs with your Entra identity (no keys).
resource "azurerm_role_assignment" "me_reader" {
  scope                = azurerm_storage_account.audit.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = data.azurerm_client_config.current.object_id
}
