# Enterprise-wide policies: set once here, inherited by every organization, and organizations can't
# loosen them. Compare with terraform/github, which governs one organization and one repository.

# Only GitHub-owned actions and an explicit allowlist of third-party actions may run anywhere in the
# enterprise. A compromised or typo-squatted action outside this list simply can't be used.
resource "github_enterprise_actions_permissions" "this" {
  enterprise_slug       = var.enterprise_slug
  enabled_organizations = "all"
  allowed_actions       = "selected"

  allowed_actions_config {
    github_owned_allowed = true  # actions/*, github/*
    verified_allowed     = false # "verified creator" is not the same as "reviewed by us"
    patterns_allowed = [
      "jfrog/setup-jfrog-cli@*",
      "sigstore/cosign-installer@*",
    ]
  }
}

# The GITHUB_TOKEN is read-only unless a workflow asks for more (as ours do, per job), and
# workflows can't approve pull requests (that would bypass the review requirement).
resource "github_enterprise_actions_workflow_permissions" "this" {
  enterprise_slug                  = var.enterprise_slug
  default_workflow_permissions     = "read"
  can_approve_pull_request_reviews = false
}

# Every new repository starts with secret scanning and push protection on.
resource "github_enterprise_security_analysis_settings" "this" {
  enterprise_slug                                              = var.enterprise_slug
  secret_scanning_enabled_for_new_repositories                 = true
  secret_scanning_push_protection_enabled_for_new_repositories = true
  secret_scanning_validity_checks_enabled                      = true
  advanced_security_enabled_for_new_repositories               = false # licence decision, see docs/day09.md
}
