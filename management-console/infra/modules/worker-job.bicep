// ============================================================================
// Container Apps Job: deploy worker
// Deployed at resource group scope (Microsoft.App/jobs is RG-scoped).
// ============================================================================

@description('Job name')
param name string

@description('Deployment region')
param location string

@description('Required tags')
param tags object

@description('Container Apps Environment resource ID')
param environmentId string

@description('User-assigned managed identity resource ID')
param uamiResourceId string

@description('User-assigned managed identity client ID (passed as env var)')
param uamiClientId string

@description('User-assigned managed identity principal (object) ID. Used to grant the API the rights to start this job.')
param uamiPrincipalId string

@description('Azure tenant ID (passed as env var)')
param tenantId string

@description('ACR login server, e.g. myregistry.azurecr.io')
param acrLoginServer string

@description('Set true once a real image has been pushed; otherwise use placeholder.')
param workerExists bool = false

@description('Application Insights connection string')
param appInsightsConnectionString string

@description('API base URL, e.g. https://api-app.azurecontainerapps.io')
param apiBaseUrl string

@description('API app registration client (application) ID — used as the token audience.')
param apiClientId string

@description('Git URL of the repo to clone (worker reads via REPO_URL env var).')
param repoUrl string = 'https://github.com/jonathan-vella/azure-smb-rf.git'

@description('Git ref (branch/tag/sha) to check out (worker reads via REPO_REF env var).')
param repoRef string = 'main'

@description('Storage account name (passed to worker as env var).')
param storageAccountName string = ''

@description('Primary blob endpoint of the app storage account.')
param storageBlobEndpoint string = ''

module imageLookup 'worker-image-lookup.bicep' = if (workerExists) {
  name: 'worker-image-lookup'
  params: {
    name: name
  }
}
var workerImage = workerExists ? imageLookup!.outputs.image : 'mcr.microsoft.com/k8se/quickstart:latest'

resource workerJob 'Microsoft.App/jobs@2024-03-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiResourceId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 3600
      replicaRetryLimit: 0
      manualTriggerConfig: {
        replicaCompletionCount: 1
        parallelism: 1
      }
      registries: [
        {
          server: acrLoginServer
          identity: uamiResourceId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'worker'
          image: workerImage
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            { name: 'AZURE_CLIENT_ID', value: uamiClientId }
            { name: 'AZURE_TENANT_ID', value: tenantId }
            { name: 'API_BASE_URL', value: apiBaseUrl }
            { name: 'API_CLIENT_ID', value: apiClientId }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
            { name: 'REPO_URL', value: repoUrl }
            { name: 'REPO_REF', value: repoRef }
            { name: 'STORAGE_ACCOUNT_NAME', value: storageAccountName }
            { name: 'STORAGE_BLOB_ENDPOINT', value: storageBlobEndpoint }
          ]
        }
      ]
    }
  }
}

output name string = workerJob.name

// ----------------------------------------------------------------------------
// Role assignment: allow the API UAMI to start this job.
// 'Container Apps Jobs Operator' (b9a307c4-...) includes Microsoft.App/jobs/*/action,
// which covers Microsoft.App/jobs/start/action used by DeploymentJobLauncher.
// Without this, the API call returns 403 AuthorizationFailed.
// ----------------------------------------------------------------------------
var containerAppsJobsOperatorRoleId = 'b9a307c4-5aa3-4b52-ba60-2b17c136cd7b'

resource jobsOperatorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(workerJob.id, uamiPrincipalId, containerAppsJobsOperatorRoleId)
  scope: workerJob
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', containerAppsJobsOperatorRoleId)
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
  }
}
