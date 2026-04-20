variable "management_group_id" {
  description = "Scope of the policy assignments."
  type        = string
}

variable "assignment_location" {
  description = "Location metadata for policy assignments."
  type        = string
}

variable "allowed_vm_skus" {
  description = "Allowed VM SKUs for smb-compute-01."
  type        = list(string)
}

variable "allowed_locations" {
  description = "Allowed locations for smb-governance-01."
  type        = list(string)
}
