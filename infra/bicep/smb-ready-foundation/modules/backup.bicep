// ============================================================================
// SMB Ready Foundation - Backup (AVM-based)
// ============================================================================
// Purpose: Deploy Recovery Services Vault for VM backup using AVM
// Version: v0.2 (AVM Migration)
// AVM Module: br/public:avm/res/recovery-services/vault:0.11.1
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Azure region for resource deployment')
param location string

@description('Environment name')
@allowed([
  'dev'
  'staging'
  'prod'
  'smb'
])
param environment string

@description('Region abbreviation for naming')
param regionShort string

@description('Tags to apply to all resources')
param tags object

// ============================================================================
// Variables
// ============================================================================

// Resource naming
var vaultName = 'rsv-smbrf-${environment}-${regionShort}'

// ============================================================================
// Recovery Services Vault (AVM Module)
// ============================================================================
// Schedule: Daily at 02:00 UTC
// Retention: 30 days daily, 12 weeks weekly (Sunday), 12 months monthly (1st)
// ============================================================================

@description('Recovery Services Vault using AVM module with VM backup policy')
module recoveryVault 'br/public:avm/res/recovery-services/vault:0.11.1' = {
  name: 'deploy-${vaultName}'
  params: {
    name: vaultName
    location: location
    tags: tags
    // Soft delete settings for security
    softDeleteSettings: {
      enhancedSecurityState: 'Enabled'
      softDeleteState: 'Enabled'
      softDeleteRetentionPeriodInDays: 14
    }
    // Backup policies for Azure VMs
    backupPolicies: [
      {
        name: 'DefaultVMPolicy'
        properties: {
          backupManagementType: 'AzureIaasVM'
          instantRpRetentionRangeInDays: 2
          schedulePolicy: {
            schedulePolicyType: 'SimpleSchedulePolicy'
            scheduleRunFrequency: 'Daily'
            scheduleRunTimes: [
              '2026-01-01T02:00:00Z' // 02:00 UTC daily
            ]
          }
          retentionPolicy: {
            retentionPolicyType: 'LongTermRetentionPolicy'
            dailySchedule: {
              retentionTimes: [
                '2026-01-01T02:00:00Z'
              ]
              retentionDuration: {
                count: 30
                durationType: 'Days'
              }
            }
            weeklySchedule: {
              daysOfTheWeek: [
                'Sunday'
              ]
              retentionTimes: [
                '2026-01-01T02:00:00Z'
              ]
              retentionDuration: {
                count: 12
                durationType: 'Weeks'
              }
            }
            monthlySchedule: {
              retentionScheduleFormatType: 'Daily'
              retentionScheduleDaily: {
                daysOfTheMonth: [
                  {
                    date: 1
                    isLast: false
                  }
                ]
              }
              retentionTimes: [
                '2026-01-01T02:00:00Z'
              ]
              retentionDuration: {
                count: 12
                durationType: 'Months'
              }
            }
          }
          timeZone: 'UTC'
        }
      }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Recovery Services Vault resource ID')
output vaultId string = recoveryVault.outputs.resourceId

@description('Recovery Services Vault name')
output vaultName string = recoveryVault.outputs.name

@description('Default VM Backup Policy ID')
output defaultVmPolicyId string = '${recoveryVault.outputs.resourceId}/backupPolicies/DefaultVMPolicy'

@description('Default VM Backup Policy name')
output defaultVmPolicyName string = 'DefaultVMPolicy'
