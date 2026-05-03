// Minimal private endpoint helper. Creates a PE with one connection to the
// target resource and binds it to a single private DNS zone via a
// privateDnsZoneGroup. Keeps main.bicep readable and avoids per-AVM-version
// shape drift on `privateEndpoints` parameters.

@description('Endpoint name')
param name string

@description('Deployment region')
param location string

@description('Required tags')
param tags object

@description('Subnet resource id (snet-pe)')
param subnetId string

@description('Target Azure resource id (Cosmos account / KV / Storage account etc.)')
param privateLinkServiceId string

@description('groupId to connect to (e.g. Sql, vault, blob)')
param groupId string

@description('Private DNS zone resource id to register the PE in.')
param privateDnsZoneId string

resource pe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: name
        properties: {
          privateLinkServiceId: privateLinkServiceId
          groupIds: [groupId]
        }
      }
    ]
  }
}

resource dnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

output id string = pe.id
output name string = pe.name
