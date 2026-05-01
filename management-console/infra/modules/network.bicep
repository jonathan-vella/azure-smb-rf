// VNet + subnets + private DNS zones for the management console.
//
// Layout:
//   10.50.0.0/22  vnet
//     10.50.0.0/23   snet-cae   (Container Apps Environment infra subnet)
//     10.50.2.0/27   snet-pe    (private endpoints for Cosmos / KV / Storage)
//
// The CAE infra subnet has no NSG and no delegation here; AVM's
// app/managed-environment module attaches the workload profile and uses the
// subnet for outbound NIC placement. /23 is the minimum size accepted by
// workload-profile environments.

@description('Deployment region')
param location string

@description('Required tags')
param tags object

@description('Base name (azd env name) used to derive resource names.')
param azdEnvName string

var vnetName = 'vnet-${azdEnvName}'
var caeSubnetName = 'snet-cae'
var peSubnetName = 'snet-pe'

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.50.0.0/22']
    }
    subnets: [
      {
        name: caeSubnetName
        properties: {
          addressPrefix: '10.50.0.0/23'
          // Container Apps env consumes outbound NICs here. PE policies must
          // be Disabled for the env's NIC placement to work, but we are not
          // putting PEs in this subnet anyway.
          privateEndpointNetworkPolicies: 'Disabled'
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: peSubnetName
        properties: {
          addressPrefix: '10.50.2.0/27'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// Private DNS zones — one per service we expose via PE. They MUST be created
// in this subscription/RG and linked to the VNet for the CAE-hosted apps to
// resolve <name>.privatelink.<service>.<suffix> to the PE NIC IP.
var zoneNames = [
  'privatelink.documents.azure.com'
  'privatelink.vaultcore.azure.net'
  'privatelink.blob.${environment().suffixes.storage}'
]

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for z in zoneNames: {
  name: z
  location: 'global'
  tags: tags
}]

resource zoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (z, i) in zoneNames: {
  parent: zones[i]
  name: 'link-${vnetName}'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}]

output vnetId string = vnet.id
output vnetName string = vnet.name
output caeSubnetId string = '${vnet.id}/subnets/${caeSubnetName}'
output peSubnetId string = '${vnet.id}/subnets/${peSubnetName}'
output cosmosZoneId string = zones[0].id
output keyVaultZoneId string = zones[1].id
output blobZoneId string = zones[2].id
