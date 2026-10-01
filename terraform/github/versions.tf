terraform {
  required_version = ">= 1.6"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }

  # Local state for now (git-ignored). Moves to an Azure Storage backend on the Azure day.
}

# Auth: export GITHUB_TOKEN=$(gh auth token)
provider "github" {
  owner = var.org
}
