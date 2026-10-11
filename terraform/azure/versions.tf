terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # State lives in Azure Storage, created by scripts/azure-bootstrap.sh.
  # Settings come from ../backend.hcl:  terraform init -backend-config=../backend.hcl
  backend "azurerm" {
    key = "azure.tfstate"
  }
}

# Uses your `az login` session locally; in CI it uses GitHub OIDC (Azure day 2).
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true # lab only: lets destroy + re-create reuse the name
    }
  }
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}
