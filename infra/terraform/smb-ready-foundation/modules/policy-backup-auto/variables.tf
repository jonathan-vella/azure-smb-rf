variable "location" {
  type = string
}

variable "subscription_resource_id" {
  description = "Full subscription resource ID (e.g. /subscriptions/<GUID>)."
  type        = string
}

variable "default_vm_policy_id" {
  description = "Composite default VM backup policy ID from the backup module."
  type        = string
}
