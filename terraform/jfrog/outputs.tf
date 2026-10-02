output "repositories" {
  description = "Repository keys by type. Point clients at the virtual repos."
  value = {
    local   = local.local_repos
    remote  = local.remote_repos
    virtual = local.virtual_repos
  }
}
