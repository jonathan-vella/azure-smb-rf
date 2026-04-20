output "assignment_count" {
  description = "Number of MG-scoped policy assignments (always 1 — the initiative aggregates all policies)."
  value       = 1
}

output "initiative_policy_count" {
  description = "Number of policy definitions contained within the initiative."
  value       = local.total_policy_refs
}

output "initiative_id" {
  description = "Resource ID of the custom policy set definition (initiative)."
  value       = azurerm_management_group_policy_set_definition.smb_baseline.id
}
