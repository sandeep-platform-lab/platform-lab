locals {
  # team slug => settings
  teams = {
    platform-team = {
      description = "Owns CI/CD, infrastructure and repository governance"
      permission  = "maintain"
    }
    app-team = {
      description = "Develops lab-api"
      permission  = "push"
    }
    security-team = {
      description = "Reviews security-relevant changes"
      permission  = "triage"
    }
  }
}

data "github_repository" "lab" {
  name = var.repository
}

resource "github_team" "this" {
  for_each = local.teams

  name        = each.key
  description = each.value.description
  privacy     = "closed" # visible to all org members
}

resource "github_team_membership" "maintainer" {
  for_each = github_team.this

  team_id  = each.value.id
  username = var.maintainer
  role     = "maintainer"
}

resource "github_team_repository" "this" {
  for_each = local.teams

  team_id    = github_team.this[each.key].id
  repository = data.github_repository.lab.name
  permission = each.value.permission
}
