# GitHub Actions logs in with a short-lived OIDC token: no JFrog secrets stored in GitHub.
# The workflow requests a GitHub ID token for audience "jfrog-github"; JFrog checks the
# issuer and claims, then issues a JFrog token scoped to one group for 5 minutes.

resource "platform_oidc_configuration" "github" {
  name          = "github-actions"
  description   = "GitHub Actions in ${var.github_repository}"
  issuer_url    = "https://token.actions.githubusercontent.com"
  provider_type = "GitHub"
  audience      = "jfrog-github"
}

# Builds on main may push to dev repos.
resource "platform_oidc_identity_mapping" "main" {
  name          = "platform-lab-main"
  description   = "Pushes from main"
  provider_name = platform_oidc_configuration.github.name
  priority      = 1

  claims_json = jsonencode({
    repository = var.github_repository
    ref        = "refs/heads/main"
  })

  token_spec = {
    scope      = "applied-permissions/groups:\"${platform_group.this["${local.p}-ci"].name}\""
    expires_in = 300
  }
}

# Everything else from the repo (PRs, feature branches) is read-only.
resource "platform_oidc_identity_mapping" "other" {
  name          = "platform-lab-other"
  description   = "PRs and other branches"
  provider_name = platform_oidc_configuration.github.name
  priority      = 2

  claims_json = jsonencode({
    repository = var.github_repository
  })

  token_spec = {
    scope      = "applied-permissions/groups:\"${platform_group.this["${local.p}-ci-readonly"].name}\""
    expires_in = 300
  }
}
