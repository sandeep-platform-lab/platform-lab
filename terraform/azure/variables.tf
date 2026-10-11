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

variable "admin_ip" {
  description = "Your public IPv4 (no /32). Only this IP reaches the AKS API server and Key Vault from outside Azure. Pass at apply time: -var admin_ip=$(curl -s https://api.ipify.org). Not stored in git."
  type        = string

  validation {
    condition     = can(regex("^\\d{1,3}(\\.\\d{1,3}){3}$", var.admin_ip))
    error_message = "admin_ip must be a plain IPv4 address, e.g. 203.0.113.10."
  }
}
