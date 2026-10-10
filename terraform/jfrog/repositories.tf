# Naming convention: <project>-<package type>-<maturity>-<locator>
#   locator: local = artifacts we build, remote = proxy/cache of a public registry,
#            no suffix = virtual repo that clients actually point at.

locals {
  p = var.project_key
}

# ---------- Docker ----------

resource "artifactory_local_docker_v2_repository" "dev" {
  key                   = "${local.p}-docker-dev-local"
  project_key           = project_project.lab.key
  description           = "Images built by CI. Untested."
  max_unique_tags       = 20 # housekeeping: only the newest 20 tags per image survive
  tag_retention         = 1
  block_pushing_schema1 = true
  xray_index            = true
  project_environments  = ["DEV"]
}

resource "artifactory_local_docker_v2_repository" "prod" {
  key                   = "${local.p}-docker-prod-local"
  project_key           = project_project.lab.key
  description           = "Images promoted after passing scans. Nobody pushes here directly."
  block_pushing_schema1 = true
  xray_index            = true
  project_environments  = ["PROD"]
}

resource "artifactory_remote_docker_repository" "dockerhub" {
  key                                   = "${local.p}-docker-remote"
  project_key                           = project_project.lab.key
  description                           = "Proxy and cache of Docker Hub"
  url                                   = "https://registry-1.docker.io/"
  curated                               = var.enable_curation # evaluated by Curation (curation.tf)
  unused_artifacts_cleanup_period_hours = 1440                # housekeeping: drop cache items unused for 60 days
  enable_token_authentication           = true
  block_pushing_schema1                 = true
  external_dependencies_enabled         = false
  xray_index                            = true
  project_environments                  = ["DEV"]
}

resource "artifactory_virtual_docker_repository" "docker" {
  key                     = "${local.p}-docker"
  project_key             = project_project.lab.key
  description             = "Single Docker endpoint for builds: our dev images first, then Docker Hub"
  repositories            = [artifactory_local_docker_v2_repository.dev.key, artifactory_remote_docker_repository.dockerhub.key]
  default_deployment_repo = artifactory_local_docker_v2_repository.dev.key
  project_environments    = ["DEV"]
}

# ---------- PyPI ----------

resource "artifactory_local_pypi_repository" "local" {
  key                  = "${local.p}-pypi-local"
  project_key          = project_project.lab.key
  description          = "Internal Python packages"
  xray_index           = true
  project_environments = ["DEV"]
}

resource "artifactory_remote_pypi_repository" "pypi" {
  key                                   = "${local.p}-pypi-remote"
  project_key                           = project_project.lab.key
  description                           = "Proxy and cache of pypi.org"
  url                                   = "https://files.pythonhosted.org"
  curated                               = var.enable_curation # evaluated by Curation (curation.tf)
  unused_artifacts_cleanup_period_hours = 1440                # housekeeping: drop cache items unused for 60 days
  pypi_registry_url                     = "https://pypi.org"
  xray_index                            = true
  project_environments                  = ["DEV"]
}

resource "artifactory_virtual_pypi_repository" "pypi" {
  key                     = "${local.p}-pypi"
  project_key             = project_project.lab.key
  description             = "Single pip index: internal packages first, then pypi.org"
  repositories            = [artifactory_local_pypi_repository.local.key, artifactory_remote_pypi_repository.pypi.key]
  default_deployment_repo = artifactory_local_pypi_repository.local.key
  project_environments    = ["DEV"]
}

# ---------- Generic ----------

resource "artifactory_local_generic_repository" "evidence" {
  key                  = "${local.p}-generic-evidence-local"
  project_key          = project_project.lab.key
  description          = "SBOMs, scan reports and other build evidence"
  xray_index           = true
  project_environments = ["DEV"]
}

locals {
  local_repos = {
    docker_dev  = artifactory_local_docker_v2_repository.dev.key
    docker_prod = artifactory_local_docker_v2_repository.prod.key
    pypi        = artifactory_local_pypi_repository.local.key
    evidence    = artifactory_local_generic_repository.evidence.key
  }
  remote_repos = {
    docker = artifactory_remote_docker_repository.dockerhub.key
    pypi   = artifactory_remote_pypi_repository.pypi.key
  }
  virtual_repos = {
    docker = artifactory_virtual_docker_repository.docker.key
    pypi   = artifactory_virtual_pypi_repository.pypi.key
  }
}
