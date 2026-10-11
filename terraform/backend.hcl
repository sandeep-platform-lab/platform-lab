# Shared Terraform backend (created by scripts/azure-bootstrap.sh). Each stack sets its own key.
resource_group_name  = "rg-platform-lab"
storage_account_name = "stplatformlabf2b2b4"
container_name       = "tfstate"
use_azuread_auth     = true
