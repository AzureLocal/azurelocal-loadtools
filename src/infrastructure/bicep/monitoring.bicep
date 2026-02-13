// =============================================================================
// monitoring.bicep - Azure Local Load Tools
// =============================================================================
// Deploys Log Analytics workspace and optional Azure Monitor resources
// for centralized metric collection from load tests.
// =============================================================================

@description('Name of the Log Analytics workspace')
param workspaceName string

@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Log Analytics SKU')
@allowed([
  'PerGB2018'
  'Free'
  'Standalone'
])
param sku string = 'PerGB2018'

@description('Data retention in days')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Tags for resource organization')
param tags object = {
  project: 'azurelocal-loadtools'
  purpose: 'load-testing-monitoring'
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: sku
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 5
    }
  }
}

// Custom log table for load test metrics
resource customTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: logAnalyticsWorkspace
  name: 'AzureLocalLoadTest_CL'
  properties: {
    totalRetentionInDays: retentionInDays
    plan: 'Analytics'
    schema: {
      name: 'AzureLocalLoadTest_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'RunId_s', type: 'string' }
        { name: 'Solution_s', type: 'string' }
        { name: 'CounterName_s', type: 'string' }
        { name: 'Node_s', type: 'string' }
        { name: 'Instance_s', type: 'string' }
        { name: 'Value_d', type: 'real' }
      ]
    }
  }
}

// Alert rule: High CPU across cluster
resource highCpuAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${workspaceName}-high-cpu-alert'
  location: location
  tags: tags
  properties: {
    displayName: 'Azure Local Load Test - High CPU Alert'
    description: 'Alerts when average CPU exceeds 95% during load test'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: '''
            AzureLocalLoadTest_CL
            | where CounterName_s == "% Processor Time"
            | where Instance_s == "_Total"
            | summarize AvgCPU = avg(Value_d) by Node_s, bin(TimeGenerated, 5m)
            | where AvgCPU > 95
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
  }
}

@description('Log Analytics Workspace ID')
output workspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Log Analytics Workspace Resource ID')
output workspaceResourceId string = logAnalyticsWorkspace.id
