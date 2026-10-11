terraform {
  required_version = ">= 1.6"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }

  # State in Azure Storage: terraform init -backend-config=../backend.hcl
  backend "azurerm" {
    key = "github.tfstate"
  }
}

# Auth: export GITHUB_TOKEN=$(gh auth token)
provider "github" {
  owner = var.org
}
