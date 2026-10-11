variable "subscription_id" {
  description = "Azure subscription for the lab."
  type        = string
}

variable "location" {
  description = "Azure region. Swiss data residency: Switzerland North (primary) / West (pair)."
  type        = string
  default     = "switzerlandnorth"
}

variable "node_vm_size" {
  description = "AKS node size. This subscription has B-series quota in Switzerland North, D-series none."
  type        = string
  default     = "Standard_B2ms"
}

variable "node_count" {
  type    = number
  default = 2
}
