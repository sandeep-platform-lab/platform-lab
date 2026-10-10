# Housekeeping: keep storage, cost and noise under control without deleting anything we need.
#
# Retention rules for this lab:
#   dev images      keep the newest 10 versions per image
#   remote caches   drop anything nobody downloaded for 60 days (it can be re-fetched any time);
#                   done by the remote repos' own cleanup period, see repositories.tf
#   PyPI (internal) keep the newest 5 versions per package
#   prod, evidence  never cleaned automatically (releases and audit evidence)
#
# Anything with the property retention.keep=true is never deleted: that's how a release is pinned.
#
# A policy uses EITHER "keep last N versions" OR age/property conditions, not both (JFrog rule).
#
# JFrog requires cleanup policies to be CREATED DISABLED. Preview with scripts/housekeeping-report.sh,
# then enable the policy in the UI (or via the API) once you agree with what it would delete.

locals {
  keep_property = { "retention.keep" = ["true"] }
}

resource "artifactory_package_cleanup_policy" "dev_docker" {
  key                 = "lab-dev-docker-keep-10"
  description         = "Dev images: keep the newest 10 versions per image"
  cron_expression     = "0 0 2 ? * SAT" # Saturdays 02:00
  duration_in_minutes = 60
  enabled             = false
  skip_trashcan       = false # recoverable from the trash can for its retention period

  # Policies are created disabled (JFrog rule) and switched on by a person after a preview.
  # Terraform owns the rules; it doesn\'t fight that on/off switch.
  lifecycle {
    ignore_changes = [enabled]
  }

  search_criteria = {
    package_types        = ["docker"]
    repos                = [local.local_repos.docker_dev]
    included_packages    = ["**"]
    included_projects    = [var.project_key]
    keep_last_n_versions = 10
    excluded_properties  = local.keep_property
  }
}

# Remote caches are NOT cleaned by cleanup policies: those accept local repos only ("Specified repo
# does not exist" for remote or -cache keys). Remote repos have their own setting instead,
# unused_artifacts_cleanup_period_hours, set in repositories.tf (60 days).

resource "artifactory_package_cleanup_policy" "pypi_internal" {
  key                 = "lab-pypi-keep-5"
  description         = "Internal Python packages: keep the newest 5 versions per package"
  cron_expression     = "0 0 3 ? * SAT"
  duration_in_minutes = 30
  enabled             = false
  skip_trashcan       = false

  # Policies are created disabled (JFrog rule) and switched on by a person after a preview.
  # Terraform owns the rules; it doesn\'t fight that on/off switch.
  lifecycle {
    ignore_changes = [enabled]
  }

  search_criteria = {
    package_types        = ["pypi"]
    repos                = [local.local_repos.pypi]
    included_packages    = ["**"]
    included_projects    = [var.project_key]
    keep_last_n_versions = 5
    excluded_properties  = local.keep_property
  }
}
