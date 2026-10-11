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
    key = "github-enterprise.tfstate"
  }
}

# Enterprise APIs need a token with the admin:enterprise scope:
#   gh auth refresh -s admin:enterprise && export GITHUB_TOKEN=$(gh auth token)
provider "github" {}
