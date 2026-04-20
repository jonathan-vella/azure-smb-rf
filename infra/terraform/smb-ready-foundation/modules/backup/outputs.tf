output "vault_id" {
  value = module.rsv.resource_id
}

output "vault_name" {
  value = module.rsv.resource.name
}

output "default_vm_policy_id" {
  description = "Resource ID of the DefaultVMPolicy backup policy."
  value       = "${module.rsv.resource_id}/backupPolicies/${local.vm_policy_name}"
}
