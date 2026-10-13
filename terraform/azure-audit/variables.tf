variable "subscription_id" {
  description = "Azure subscription for the lab."
  type        = string
}

variable "location" {
  type    = string
  default = "switzerlandnorth"
}

variable "worm_enabled" {
  description = "Immutability (WORM) on the audit container. Turn off only while (re)configuring GitHub's stream: its Check endpoint overwrites a _check blob, which WORM forbids. Possible only while the policy is unlocked."
  type        = bool
  default     = true
}
