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

  # Repos and groups are attached with their own resources below.
  use_project_repository_resource = true
  use_project_group_resource      = true
}

resource "project_repository" "this" {
  for_each = merge(
    { for k, v in local.local_repos : "local-${k}" => v },
    { for k, v in local.remote_repos : "remote-${k}" => v },
    { for k, v in local.virtual_repos : "virtual-${k}" => v },
  )

  project_key = project_project.lab.key
  key         = each.value
}

resource "project_group" "admins" {
  project_key = project_project.lab.key
  name        = platform_group.this["${local.p}-platform-admins"].name
  roles       = ["Project Admin"]
}

resource "project_group" "developers" {
  project_key = project_project.lab.key
  name        = platform_group.this["${local.p}-developers"].name
  roles       = ["Developer"]
}
