variable "subscription_resource_id" {
  type = string
}

variable "amount" {
  type = number
}

variable "alert_email" {
  type = string
}

variable "start_date" {
  description = "YYYY-MM-01 — validated at root."
  type        = string
}
