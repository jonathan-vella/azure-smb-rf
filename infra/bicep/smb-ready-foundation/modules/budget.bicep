// ============================================================================
// SMB Ready Foundation - Budget
// ============================================================================
// Purpose: Deploy Cost Management Budget with alerts
// Version: v0.3
// ============================================================================
// IMPORTANT: Azure Budgets API Limitation
// ========================================
// Azure Budgets do NOT allow updating the start date after creation.
// This means redeploying with a different month will FAIL.
//
// Solution: The deploy.ps1 script automatically deletes any existing
// budget before deployment, ensuring a clean state.
//
// If deploying manually (not via deploy.ps1), run:
//   az consumption budget delete --budget-name 'budget-smb-monthly'
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Monthly budget amount in USD')
@minValue(100)
@maxValue(10000)
param budgetAmount int = 500

@description('Email address for budget alerts')
param alertEmail string

@description('Budget start date (first day of month, format: yyyy-MM-dd). MUST be fixed - cannot be updated after creation.')
param startDate string

// ============================================================================
// Variables
// ============================================================================

// Budget naming
var budgetName = 'budget-smb-monthly'

// Calculate start date for budget (use first of current month if not provided)
var budgetStartDate = '${substring(startDate, 0, 8)}01'

// ============================================================================
// Cost Management Budget
// ============================================================================

@description('Monthly budget with 80% forecast and 100% actual alerts')
resource budget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: budgetName
  properties: {
    category: 'Cost'
    amount: budgetAmount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: budgetStartDate
    }
    notifications: {
      forecastAlert80: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        contactEmails: [
          alertEmail
        ]
        thresholdType: 'Forecasted'
        locale: 'en-us'
      }
      actualAlert90: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 90
        contactEmails: [
          alertEmail
        ]
        thresholdType: 'Actual'
        locale: 'en-us'
      }
      actualAlert100: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        contactEmails: [
          alertEmail
        ]
        thresholdType: 'Actual'
        locale: 'en-us'
      }
    }
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Budget resource ID')
output budgetId string = budget.id

@description('Budget name')
output budgetName string = budget.name
