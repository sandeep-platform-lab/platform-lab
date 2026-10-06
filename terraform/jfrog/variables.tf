variable "project_key" {
  description = "JFrog Project key. Also the prefix of every repository key."
  type        = string
  default     = "lab"
}

variable "github_repository" {
  description = "GitHub repo (owner/name) whose Actions workflows may log in to JFrog via OIDC."
  type        = string
  default     = "sandeep-platform-lab/platform-lab"
}
