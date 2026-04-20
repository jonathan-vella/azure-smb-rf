variable "name" {
  description = "Management group name (id)."
  type        = string
}

variable "display_name" {
  description = "Management group display name."
  type        = string
}

variable "subscription_id" {
  description = "Target subscription GUID to associate under the management group."
  type        = string
}
