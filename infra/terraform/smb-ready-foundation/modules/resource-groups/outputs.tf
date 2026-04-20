output "shared" {
  description = "Map keyed by RG role (hub/monitor/backup/migrate/security) to { name, id }."
  value = {
    for k, rg in azurerm_resource_group.shared : k => {
      name = rg.name
      id   = rg.id
    }
  }
}

output "spoke" {
  description = "Spoke RG { name, id }."
  value = {
    name = azurerm_resource_group.spoke.name
    id   = azurerm_resource_group.spoke.id
  }
}
