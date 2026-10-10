# The production environment: jobs that use it pause until a platform-team member approves, and
# only main may deploy to it. JFrog's OIDC trust maps "environment = production" to the release
# group, so approval in GitHub is what unlocks write access to the prod repo.
resource "github_repository_environment" "production" {
  repository  = data.github_repository.lab.name
  environment = "production"

  prevent_self_review = false # one-person lab; in a real team, set true (four-eyes principle)
  can_admins_bypass   = false # even org admins wait for an approval

  reviewers {
    teams = [tonumber(github_team.this["platform-team"].id)]
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true # explicit list below; "protected branches" may not count rulesets
  }
}

resource "github_repository_environment_deployment_policy" "production_main" {
  repository     = data.github_repository.lab.name
  environment    = github_repository_environment.production.environment
  branch_pattern = "main"
}
