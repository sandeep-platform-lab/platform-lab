# Curation: decides what may enter Artifactory from public registries, BEFORE it's downloaded and
# cached. Xray finds problems in what you already have; Curation stops them arriving.
# Condition IDs are JFrog's built-in conditions (GET /xray/api/v1/curation/conditions).
#
# Needs a Catalog/Curation entitlement. The free trial reports "entitled_for_catalog": false
# (GET /catalog/api/v1/system/app_health), so this is off unless enable_curation = true.

locals {
  curation_conditions = {
    malicious        = "1"  # Malicious package
    cvss9_with_fix   = "2"  # CVE with CVSS 9+ (fix version available)
    cvss7_with_fix   = "4"  # CVE with CVSS 7.0–8.9 (fix version available)
    not_official_hub = "18" # Image is not Docker Hub official
  }
}

resource "xray_curation_policy" "malicious" {
  count = var.enable_curation ? 1 : 0

  name          = "lab-block-malicious"
  condition_id  = local.curation_conditions.malicious
  scope         = "specific_repos"
  repo_include  = values(local.remote_repos)
  policy_action = "block"
}

resource "xray_curation_policy" "cvss9" {
  count = var.enable_curation ? 1 : 0

  name          = "lab-block-cvss9-with-fix"
  condition_id  = local.curation_conditions.cvss9_with_fix
  scope         = "specific_repos"
  repo_include  = values(local.remote_repos)
  policy_action = "block"
}

# Stricter for Python packages: a fix exists, so developers should use it.
resource "xray_curation_policy" "pypi_cvss7" {
  count = var.enable_curation ? 1 : 0

  name          = "lab-block-pypi-cvss7-with-fix"
  condition_id  = local.curation_conditions.cvss7_with_fix
  scope         = "specific_repos"
  repo_include  = [local.remote_repos.pypi]
  policy_action = "block"
}

# Dry run: log which images WOULD be blocked, without breaking anyone. Measure first, then enforce.
resource "xray_curation_policy" "unofficial_images" {
  count = var.enable_curation ? 1 : 0

  name          = "lab-dryrun-unofficial-images"
  condition_id  = local.curation_conditions.not_official_hub
  scope         = "specific_repos"
  repo_include  = [local.remote_repos.docker]
  policy_action = "dry_run"
}
