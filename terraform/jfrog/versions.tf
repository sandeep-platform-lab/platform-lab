terraform {
  required_version = ">= 1.6"

  required_providers {
    artifactory = {
      source  = "jfrog/artifactory"
      version = ">= 12.0"
    }
    platform = {
      source  = "jfrog/platform"
      version = ">= 2.0"
    }
    project = {
      source  = "jfrog/project"
      version = ">= 1.9"
    }
  }
}

# Auth for all three providers: export JFROG_URL and JFROG_ACCESS_TOKEN (see .env).
provider "artifactory" {}
provider "platform" {}
provider "project" {}
