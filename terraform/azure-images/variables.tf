variable "subscription_id" {
  description = "Azure subscription for the lab."
  type        = string
}

variable "location" {
  type    = string
  default = "switzerlandnorth"
}
