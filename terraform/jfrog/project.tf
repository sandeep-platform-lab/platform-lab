# A JFrog Project groups repos, members, roles and (later) Xray policies for one team or product.

resource "project_project" "lab" {
  key                        = var.project_key
  display_name               = "Platform Lab"
  description                = "Secure supply-chain lab"
  max_storage_in_gibibytes   = 10
  block_deployments_on_limit = false
  email_notification         = false

  admin_privileges {
    manage_members   = true
    manage_resources = true
    index_resources  = true
  }

  # Groups are attached with their own resources below; repos set project_key themselves.
  use_project_repository_resource = true
  use_project_group_resource      = true
}

# Repos join the project through project_key on each repository (repositories.tf).
# project_repository was removed: it fought with the repo resources over project_key.
# "removed" forgets it from state WITHOUT detaching the repos from the project.
removed {
  from = project_repository.this

  lifecycle {
    destroy = false
  }
}

resource "project_group" "admins" {
  project_key = project_project.lab.key
  name        = platform_group.this["${local.p}-platform-admins"].name
  roles       = ["Project Admin"]
}

# Built-in project roles are broad: "Developer" includes DEPLOY and DELETE/OVERWRITE on every
# DEV repo. Effective rights are the UNION of global permissions and project roles, so that role
# silently let developers push. This custom role keeps them read-only, as access.tf intends.
resource "project_role" "reader" {
  project_key  = project_project.lab.key
  name         = "Reader"
  type         = "CUSTOM"
  environments = ["DEV", "PROD"]
  actions = [
    "READ_REPOSITORY",
    "ANNOTATE_REPOSITORY",
    "READ_BUILD",
    "ANNOTATE_BUILD",
    "READ_RELEASE_BUNDLE",
  ]
}

resource "project_group" "developers" {
  project_key = project_project.lab.key
  name        = platform_group.this["${local.p}-developers"].name
  roles       = [project_role.reader.name]
}
