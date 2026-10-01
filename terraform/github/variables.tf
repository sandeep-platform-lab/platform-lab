variable "org" {
  description = "GitHub organization that owns the lab."
  type        = string
  default     = "sandeep-platform-lab"
}

variable "repository" {
  description = "Repository the governance applies to."
  type        = string
  default     = "platform-lab"
}

variable "maintainer" {
  description = "GitHub username added as maintainer of every team."
  type        = string
  default     = "skumaraz2k7"
}
