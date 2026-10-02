# Groups describe roles; permissions say what each role may do where.
# People and pipelines get access only through groups.

locals {
  groups = {
    "${local.p}-platform-admins" = "Platform team: manages the lab project"
    "${local.p}-developers"      = "Developers: read everything, annotate, never push"
    "${local.p}-ci"              = "CI pipelines on main: push to dev repos, publish build-info"
    "${local.p}-ci-readonly"     = "CI pipelines on PRs and other branches: read only"
    "${local.p}-release"         = "Promotion jobs: the only writers to prod"
  }
}

resource "platform_group" "this" {
  for_each = local.groups

  name        = each.key
  description = each.value
  auto_join   = false
}

# Developers and PR pipelines: read anything, cache from remotes (needs WRITE on remotes).
resource "platform_permission" "read" {
  name = "${local.p}-read"

  artifact = {
    actions = {
      groups = [
        { name = platform_group.this["${local.p}-developers"].name, permissions = ["READ", "ANNOTATE"] },
        { name = platform_group.this["${local.p}-ci-readonly"].name, permissions = ["READ"] },
      ]
    }
    targets = [for k in concat(values(local.local_repos), values(local.virtual_repos)) : { name = k, include_patterns = ["**"] }]
  }
}

resource "platform_permission" "remote_cache" {
  name = "${local.p}-remote-cache"

  artifact = {
    actions = {
      groups = [for g in ["developers", "ci", "ci-readonly", "release"] :
        { name = platform_group.this["${local.p}-${g}"].name, permissions = ["READ", "WRITE"] }
      ]
    }
    targets = [for k in values(local.remote_repos) : { name = k, include_patterns = ["**"] }]
  }
}

# CI on main: push to dev, upload evidence, publish build-info. No delete, no prod.
resource "platform_permission" "ci_deploy" {
  name = "${local.p}-ci-deploy"

  artifact = {
    actions = {
      groups = [{ name = platform_group.this["${local.p}-ci"].name, permissions = ["READ", "WRITE", "ANNOTATE"] }]
    }
    targets = [for k in [local.local_repos.docker_dev, local.local_repos.pypi, local.local_repos.evidence, local.virtual_repos.docker, local.virtual_repos.pypi] :
      { name = k, include_patterns = ["**"] }
    ]
  }

  build = {
    actions = {
      groups = [
        { name = platform_group.this["${local.p}-ci"].name, permissions = ["READ", "WRITE", "ANNOTATE"] },
        { name = platform_group.this["${local.p}-developers"].name, permissions = ["READ"] },
        { name = platform_group.this["${local.p}-release"].name, permissions = ["READ"] },
      ]
    }
    targets = [{ name = "artifactory-build-info", include_patterns = ["**"] }]
  }
}

# Promotion: copy from dev to prod. Segregation of duties: CI can't write prod, release can't write dev.
resource "platform_permission" "release" {
  name = "${local.p}-release"

  artifact = {
    actions = {
      groups = [{ name = platform_group.this["${local.p}-release"].name, permissions = ["READ", "WRITE", "ANNOTATE"] }]
    }
    targets = [{ name = local.local_repos.docker_prod, include_patterns = ["**"] }]
  }
}

# Admins of the lab: full control of the lab repos only (not of the whole platform).
resource "platform_permission" "admin" {
  name = "${local.p}-admin"

  artifact = {
    actions = {
      groups = [{ name = platform_group.this["${local.p}-platform-admins"].name, permissions = ["READ", "WRITE", "ANNOTATE", "DELETE", "MANAGE", "SCAN"] }]
    }
    targets = [for k in concat(values(local.local_repos), values(local.remote_repos), values(local.virtual_repos)) : { name = k, include_patterns = ["**"] }]
  }
}
