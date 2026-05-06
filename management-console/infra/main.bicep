// ============================================================================
// Partner Management Console - Main Orchestration Template
// ============================================================================
// Purpose: Hosts the .NET 10 API + React SPA + deploy worker (Container Apps Job)
//          that partners use to onboard customer subscriptions via Lighthouse
//          and deploy smb-ready-foundation (Bicep) into them.
// Scope:   Subscription (creates RG + resources)
// ============================================================================

targetScope = 'subscription'

// ----------------------------------------------------------------------------
// Parameters
// ----------------------------------------------------------------------------

@description('Primary deployment region')
@allowed(['swedencentral', 'germanywestcentral', 'westeurope', 'northeurope'])
param location string

@description('Environment name for resource naming and tagging')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'prod'

@description('Owner email or team name (required tag). Override with `azd env set OWNER ...`.')
param owner string = 'partner-ops'

@description('Entra tenant ID hosting the partner console (single-tenant).')
param partnerTenantId string = subscription().tenantId

@description('Application (client) ID of the API app registration. Populated by the preprovision hook.')
param apiAppClientId string = ''

@description('Application (client) ID of the SPA app registration. Populated by the preprovision hook.')
param spaAppClientId string = ''

@description('Comma-separated additional partner principal IDs (Entra group object IDs or user object IDs) to grant access via Lighthouse. These appear in the customer\'s registrationDefinition authorizations alongside the partner UAMI, and are what makes the customer visible under "My customers" in the partner tenant for human admins.')
param partnerAdminPrincipalIds string = ''

@description('Object ID of the AZURE-SMB-RF-MANAGEMENT Entra group (created by preprovision hook). Granted Lighthouse delegation alongside the UAMI so the partner staff who are members of the group see the customer subscription in their portal.')
param securityGroupObjectId string = ''

@description('Object ID of the principal running azd (set by preprovision hook from `az ad signed-in-user show`). Granted Cosmos data-plane access so the deployer can query the DB locally; empty string skips.')
param deployerPrincipalId string = ''

// azd convention: on first run no image exists in ACR yet, so we provision the
// container apps with a public placeholder and let `azd deploy` build/push the
// real image and update the revision. On subsequent runs `*Exists=true` keeps
// whatever image is already deployed.
@description('Set true if the API container app already has a real image deployed.')
param apiExists bool = false

@description('Set true if the Web container app already has a real image deployed.')
param webExists bool = false

@description('Set true if the worker job already has a real image deployed.')
param workerExists bool = false

@description('azd environment name (used by azd to discover deployed resources via tags).')
param azdEnvName string

@description('Git URL of the repo containing infra/ and management-console/lighthouse/delegation.json. Override with `azd env set REPO_URL ...` to point at a fork or feature branch.')
param repoUrl string = 'https://github.com/jonathan-vella/azure-smb-rf.git'

@description('Git ref (branch, tag, or commit SHA) to deploy from. Override with `azd env set REPO_REF ...`.')
param repoRef string = 'main'

// Derive an `owner/name` slug from repoUrl for the PrerequisitesTemplateService
// (which downloads the foundation ARM template from a GitHub release zipball
// rather than cloning). Strips a trailing `.git` and the `https://github.com/`
// prefix so an HTTPS clone URL maps cleanly to the GitHub API path.
var repoUrlNoGit = endsWith(repoUrl, '.git') ? substring(repoUrl, 0, length(repoUrl) - 4) : repoUrl
var repoSlug = replace(repoUrlNoGit, 'https://github.com/', '')

var placeholderImage = 'mcr.microsoft.com/k8se/quickstart:latest'

// ----------------------------------------------------------------------------
// Variables
// ----------------------------------------------------------------------------

// All resource names derive from the azd environment name so deployments are
// consistent across `azd env new <name>` invocations. `suffix` adds entropy
// for resources that require a globally unique name (KV, ACR, Cosmos).
var suffix = uniqueString(subscription().id, azdEnvName)
var rgName = 'rg-${azdEnvName}'
// ACR allows alphanumerics only (no hyphens), so flatten the env name.
var acrEnvName = replace(azdEnvName, '-', '')
// azd uses these tags to discover the RG and to map services to deployed
// container apps/jobs. The env name comes from `azd env new <name>`.
var tags = {
  Environment: environment
  ManagedBy: 'Bicep'
  Project: 'partner-management-console'
  Owner: owner
  'azd-env-name': azdEnvName
}

// ----------------------------------------------------------------------------
// Resource Group
// ----------------------------------------------------------------------------

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: tags
}

// ----------------------------------------------------------------------------
// User-Assigned Managed Identity
// Used by API + Worker to act in customer subscriptions via Lighthouse.
// ----------------------------------------------------------------------------

module uami 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'uami-deploy'
  scope: rg
  params: {
    name: 'id-${azdEnvName}'
    location: location
    tags: tags
  }
}

// ----------------------------------------------------------------------------
// Log Analytics + Application Insights
// ----------------------------------------------------------------------------

module law 'br/public:avm/res/operational-insights/workspace:0.7.0' = {
  name: 'law'
  scope: rg
  params: {
    name: 'log-${azdEnvName}'
    location: location
    tags: tags
    dataRetention: 30
    skuName: 'PerGB2018'
  }
}

module appi 'br/public:avm/res/insights/component:0.4.1' = {
  name: 'appi'
  scope: rg
  params: {
    name: 'appi-${azdEnvName}'
    location: location
    tags: tags
    workspaceResourceId: law.outputs.resourceId
    applicationType: 'web'
  }
}

// ----------------------------------------------------------------------------
// VNet + private DNS zones
// ----------------------------------------------------------------------------

module network 'modules/network.bicep' = {
  name: 'network'
  scope: rg
  params: {
    location: location
    tags: tags
    azdEnvName: azdEnvName
  }
}

// ----------------------------------------------------------------------------
// Key Vault (private — public access disabled, reachable via PE only)
// ----------------------------------------------------------------------------

module kv 'br/public:avm/res/key-vault/vault:0.10.0' = {
  name: 'kv'
  scope: rg
  params: {
    name: take('kv-${azdEnvName}-${suffix}', 24)
    location: location
    tags: tags
    sku: 'standard'
    enableRbacAuthorization: true
    enableSoftDelete: true
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    roleAssignments: [
      {
        // Officer (read+write) is required because the API generates and
        // stores VPN pre-shared keys here per customer environment when the
        // partner connects the customer's foundation to their on-prem VPN
        // appliance. Without write, only read of pre-existing secrets works.
        principalId: uami.outputs.principalId
        roleDefinitionIdOrName: 'Key Vault Secrets Officer'
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

module kvPe 'modules/private-endpoint.bicep' = {
  name: 'pe-kv'
  scope: rg
  params: {
    name: 'pe-kv-${azdEnvName}'
    location: location
    tags: tags
    subnetId: network.outputs.peSubnetId
    privateLinkServiceId: kv.outputs.resourceId
    groupId: 'vault'
    privateDnsZoneId: network.outputs.keyVaultZoneId
  }
}

// ----------------------------------------------------------------------------
// Container Registry (partner-owned worker image)
// ----------------------------------------------------------------------------

module acr 'br/public:avm/res/container-registry/registry:0.5.1' = {
  name: 'acr'
  scope: rg
  params: {
    name: take('cr${acrEnvName}${suffix}', 50)
    location: location
    tags: tags
    acrSku: 'Basic'
    acrAdminUserEnabled: false
    publicNetworkAccess: 'Enabled'
    roleAssignments: [
      {
        principalId: uami.outputs.principalId
        roleDefinitionIdOrName: 'AcrPull'
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

// ----------------------------------------------------------------------------
// Cosmos DB (serverless SQL) — app metadata
// ----------------------------------------------------------------------------

module cosmos 'br/public:avm/res/document-db/database-account:0.8.1' = {
  name: 'cosmos'
  scope: rg
  params: {
    name: take('cosmos-${azdEnvName}-${suffix}', 44)
    location: location
    tags: tags
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilitiesToAdd: ['EnableServerless']
    networkRestrictions: {
      publicNetworkAccess: 'Disabled'
      ipRules: []
      virtualNetworkRules: []
      networkAclBypass: 'AzureServices'
    }
    sqlDatabases: [
      {
        name: 'console'
        containers: [
          { name: 'customers', paths: ['/tenantId'] }
          { name: 'deployments', paths: ['/customerId'] }
          { name: 'auditLog', paths: ['/customerId'] }
          { name: 'settings', paths: ['/id'] }
        ]
      }
    ]
    sqlRoleAssignmentsPrincipalIds: filter([uami.outputs.principalId, securityGroupObjectId, deployerPrincipalId], p => !empty(p))
    sqlRoleDefinitions: [
      {
        name: 'CustomReadWriteRole'
        dataAction: [
          'Microsoft.DocumentDB/databaseAccounts/readMetadata'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/*'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/executeQuery'
        ]
      }
    ]
  }
}

module cosmosPe 'modules/private-endpoint.bicep' = {
  name: 'pe-cosmos'
  scope: rg
  params: {
    name: 'pe-cosmos-${azdEnvName}'
    location: location
    tags: tags
    subnetId: network.outputs.peSubnetId
    privateLinkServiceId: cosmos.outputs.resourceId
    groupId: 'Sql'
    privateDnsZoneId: network.outputs.cosmosZoneId
  }
}

// ----------------------------------------------------------------------------
// Storage account (private blob, app data)
// ----------------------------------------------------------------------------

var storageAccountName = take(replace('st${azdEnvName}${suffix}', '-', ''), 24)

module storage 'br/public:avm/res/storage/storage-account:0.14.3' = {
  name: 'storage'
  scope: rg
  params: {
    name: storageAccountName
    location: location
    tags: tags
    skuName: 'Standard_LRS'
    kind: 'StorageV2'
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Disabled'
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    blobServices: {
      containers: [
        { name: 'app-data' }
      ]
    }
    roleAssignments: [
      {
        principalId: uami.outputs.principalId
        roleDefinitionIdOrName: 'Storage Blob Data Contributor'
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

module storagePe 'modules/private-endpoint.bicep' = {
  name: 'pe-storage'
  scope: rg
  params: {
    name: 'pe-st-${azdEnvName}'
    location: location
    tags: tags
    subnetId: network.outputs.peSubnetId
    privateLinkServiceId: storage.outputs.resourceId
    groupId: 'blob'
    privateDnsZoneId: network.outputs.blobZoneId
  }
}

// ----------------------------------------------------------------------------
// Container Apps Environment
// ----------------------------------------------------------------------------

// VNet-integrated, external (web stays public, API uses internal-only ingress).
module cae 'br/public:avm/res/app/managed-environment:0.8.1' = {
  name: 'cae'
  scope: rg
  params: {
    name: 'cae-${azdEnvName}'
    location: location
    tags: tags
    logAnalyticsWorkspaceResourceId: law.outputs.resourceId
    zoneRedundant: false
    infrastructureSubnetId: network.outputs.caeSubnetId
    internal: false
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

// Lookup the env's default domain so we can compute the web FQDN before the
// web container app exists (used by API CORS env var).
resource caeExisting 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: 'cae-${azdEnvName}'
  scope: rg
  dependsOn: [cae]
}
var webFqdn = 'ca-web-${azdEnvName}.${caeExisting.properties.defaultDomain}'

// ----------------------------------------------------------------------------
// Container App: API
// ----------------------------------------------------------------------------

// On re-runs azd flips apiExists=true; pull the currently-deployed image so
// provisioning is image-neutral and `azd deploy` is what updates it.
resource existingApiApp 'Microsoft.App/containerApps@2024-03-01' existing = if (apiExists) {
  name: 'ca-api-${azdEnvName}'
  scope: rg
}
var apiImage = apiExists ? existingApiApp.?properties.template.containers[0].image ?? placeholderImage : placeholderImage

module apiApp 'br/public:avm/res/app/container-app:0.11.0' = {
  name: 'app-api'
  scope: rg
  params: {
    name: 'ca-api-${azdEnvName}'
    location: location
    tags: union(tags, { 'azd-service-name': 'api' })
    environmentResourceId: cae.outputs.resourceId
    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [uami.outputs.resourceId]
    }
    // Internal-only ingress: API is only reachable from inside the CAE
    // (i.e. the web container app). Public traffic goes through web/nginx
    // which proxies /api -> this internal FQDN.
    ingressExternal: false
    ingressTargetPort: 8080
    ingressTransport: 'auto'
    ingressAllowInsecure: false
    registries: [
      {
        server: '${acr.outputs.name}.azurecr.io'
        identity: uami.outputs.resourceId
      }
    ]
    containers: [
      {
        name: 'api'
        image: apiImage
        resources: {
          cpu: json('0.5')
          memory: '1Gi'
        }
        env: [
          { name: 'AZURE_CLIENT_ID', value: uami.outputs.clientId }
          { name: 'AZURE_TENANT_ID', value: partnerTenantId }
          { name: 'COSMOS_ENDPOINT', value: cosmos.outputs.endpoint }
          { name: 'COSMOS_DATABASE', value: 'console' }
          { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appi.outputs.connectionString }
          { name: 'KEY_VAULT_URI', value: kv.outputs.uri }
          { name: 'API_AUDIENCE', value: 'api://${apiAppClientId}' }
          { name: 'API_CLIENT_ID', value: apiAppClientId }
          { name: 'SPA_CLIENT_ID', value: spaAppClientId }
          // Microsoft.Identity.Web reads AzureAd:* from configuration. .NET
          // does NOT expand ${...} placeholders in appsettings.json, so we
          // must surface these as proper env vars (double-underscore = colon).
          { name: 'AzureAd__Instance', value: 'https://login.microsoftonline.com/' }
          { name: 'AzureAd__TenantId', value: partnerTenantId }
          { name: 'AzureAd__ClientId', value: apiAppClientId }
          { name: 'AzureAd__Audience', value: 'api://${apiAppClientId}' }
          { name: 'WORKER_JOB_NAME', value: 'caj-worker-${azdEnvName}' }
          { name: 'WORKER_RG', value: rgName }
          { name: 'WORKER_SUBSCRIPTION_ID', value: subscription().subscriptionId }
          { name: 'Lighthouse__PartnerPrincipalIds', value: trim(join(filter([uami.outputs.principalId, securityGroupObjectId, partnerAdminPrincipalIds], p => !empty(p)), ',')) }
          { name: 'Repo__Url', value: repoUrl }
          { name: 'Repo__Ref', value: repoRef }
          // PrerequisitesTemplateService pulls deploy-mg.json + policy initiative
          // from the same repo/ref the worker clones, so the customer's MG +
          // policies match the foundation version the worker provisions.
          { name: 'Prerequisites__TemplateSource__Repo', value: repoSlug }
          { name: 'Prerequisites__TemplateSource__Tag', value: repoRef }
          { name: 'Spa__Origin', value: 'https://${webFqdn}' }
          { name: 'Storage__BlobEndpoint', value: storage.outputs.primaryBlobEndpoint }
          { name: 'Storage__AccountName', value: storage.outputs.name }
        ]
      }
    ]
    scaleMinReplicas: 1
    scaleMaxReplicas: 3
  }
}

// ----------------------------------------------------------------------------
// Container App: Web (SPA)
// ----------------------------------------------------------------------------

resource existingWebApp 'Microsoft.App/containerApps@2024-03-01' existing = if (webExists) {
  name: 'ca-web-${azdEnvName}'
  scope: rg
}
var webImage = webExists ? existingWebApp.?properties.template.containers[0].image ?? placeholderImage : placeholderImage

module webApp 'br/public:avm/res/app/container-app:0.11.0' = {
  name: 'app-web'
  scope: rg
  params: {
    name: 'ca-web-${azdEnvName}'
    location: location
    tags: union(tags, { 'azd-service-name': 'web' })
    environmentResourceId: cae.outputs.resourceId
    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [uami.outputs.resourceId]
    }
    ingressExternal: true
    ingressTargetPort: 80
    ingressTransport: 'auto'
    ingressAllowInsecure: false
    registries: [
      {
        server: '${acr.outputs.name}.azurecr.io'
        identity: uami.outputs.resourceId
      }
    ]
    containers: [
      {
        name: 'web'
        image: webImage
        resources: {
          cpu: json('0.25')
          memory: '0.5Gi'
        }
        env: [
          { name: 'API_BASE_URL', value: 'https://${apiApp.outputs.fqdn}' }
        ]
      }
    ]
    scaleMinReplicas: 1
    scaleMaxReplicas: 2
  }
}

// ----------------------------------------------------------------------------
// Container Apps Job: deploy worker
// One job, manually triggered per deployment by the API. Wrapped in a module
// because Microsoft.App/jobs is RG-scoped and main.bicep targets subscription.
// ----------------------------------------------------------------------------

module workerJob 'modules/worker-job.bicep' = {
  name: 'worker-job'
  scope: rg
  params: {
    name: 'caj-worker-${azdEnvName}'
    location: location
    tags: union(tags, { 'azd-service-name': 'worker' })
    environmentId: cae.outputs.resourceId
    uamiResourceId: uami.outputs.resourceId
    uamiClientId: uami.outputs.clientId
    uamiPrincipalId: uami.outputs.principalId
    tenantId: partnerTenantId
    acrLoginServer: '${acr.outputs.name}.azurecr.io'
    workerExists: workerExists
    appInsightsConnectionString: appi.outputs.connectionString
    repoUrl: repoUrl
    repoRef: repoRef
    apiBaseUrl: 'https://${apiApp.outputs.fqdn}'
    apiClientId: apiAppClientId
    storageAccountName: storage.outputs.name
    storageBlobEndpoint: storage.outputs.primaryBlobEndpoint
  }
}

// ----------------------------------------------------------------------------
// Outputs (SCREAMING_SNAKE_CASE for consistency with azd conventions and so
// hooks/runtime config can use ordinary $env:NAME / Environment.GetEnvironmentVariable lookups)
// ----------------------------------------------------------------------------

output RESOURCE_GROUP_NAME string = rg.name
output API_FQDN string = apiApp.outputs.fqdn
output WEB_FQDN string = webApp.outputs.fqdn
output UAMI_PRINCIPAL_ID string = uami.outputs.principalId
// azd remote-build looks for this exact env var name to know where to push images.
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = '${acr.outputs.name}.azurecr.io'
output COSMOS_ENDPOINT string = cosmos.outputs.endpoint
output WORKER_JOB_NAME string = workerJob.outputs.name
output STORAGE_ACCOUNT_NAME string = storage.outputs.name
output STORAGE_BLOB_ENDPOINT string = storage.outputs.primaryBlobEndpoint
output VNET_NAME string = network.outputs.vnetName
