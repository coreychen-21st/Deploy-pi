// =============================================================================
// App Service 模組 - Linux Container + VNet Integration + IP 白名單限制 + Managed Identity
// =============================================================================

targetScope = 'resourceGroup'

@description('位置')
param location string

@description('App Service 名稱')
param appServiceName string

@description('App Service Plan 名稱')
param appServicePlanName string

@description('VNet Resource ID')
param vnetId string

@description('Web App Subnet Resource ID')
param webAppSubnetId string

@description('SQL Server Resource ID')
param sqlServerId string

@description('Redis Resource ID')
param redisId string

@description('Entra ID WebAppExecutor Group Object ID - DB-Ewa-Prod-WebAppExecutor')
param entraWebAppExecutorGroupObjectId string

@description('App Service Plan SKU')
param appServicePlanSku string = 'P0v3'

@description('Docker Image')
param dockerImage string = ''

@description('Runtime Stack')
param runtimeStack string = 'DOTNETCORE:8.0'

// =============================================================================
// 辦公室 IP 白名單 (Main Site)
// =============================================================================
var ipRestrictionRules = [
  {
    name: 'Office_2F'
    ipAddress: '218.32.244.152/32'
    action: 'Allow'
    priority: 100
    description: '樂分期 2 樓'
  }
  {
    name: 'IT_143_IP'
    ipAddress: '210.243.135.140/32'
    action: 'Allow'
    priority: 100
    description: 'Allow-IT-143-IP'
  }
  {
    name: 'Pi_OA'
    ipAddress: '59.124.7.175/32'
    action: 'Allow'
    priority: 101
    description: 'Allow-Pi-OA'
  }
  {
    name: 'Pitest_Internal'
    ipAddress: '4.190.186.188/32'
    action: 'Allow'
    priority: 102
    description: 'Allow-pitest-internal'
  }
  {
    name: 'Office_143_2F_Range1'
    ipAddress: '125.227.46.135/31'
    action: 'Allow'
    priority: 113
    description: 'office_143_2f'
  }
  {
    name: 'Office_143_2F_Range2'
    ipAddress: '219.70.120.125/32'
    action: 'Allow'
    priority: 123
    description: 'office_143_2f'
  }
  {
    name: 'Office_163'
    ipAddress: '210.242.238.172/32'
    action: 'Allow'
    priority: 133
    description: 'office_163_2f3f5f8f10f'
  }
  {
    name: 'Office_143_All'
    ipAddress: '219.86.43.106/31'
    action: 'Allow'
    priority: 143
    description: 'office_143_2f3f5f8f10f'
  }
]

// =============================================================================
// App Service Plan
// =============================================================================
resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: appServicePlanName
  location: location
  kind: 'linux'
  sku: {
    name: appServicePlanSku
    tier: 'PremiumV3'
    capacity: 1
  }
  properties: {
    reserved: true
    zoneRedundant: false
  }
}

// =============================================================================
// App Service (Linux)
// =============================================================================
resource appService 'Microsoft.Web/sites@2024-04-01' = {
  name: appServiceName
  location: location
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    clientAffinityEnabled: false
    clientCertEnabled: false
    siteConfig: {
      linuxFxVersion: !empty(dockerImage) ? 'DOCKER|${dockerImage}' : runtimeStack
      alwaysOn: true
      http20Enabled: false
      minTlsVersion: '1.2'
      ftpsState: 'FtpsOnly'
      use32BitWorkerProcess: true
      webSocketsEnabled: false
      remoteDebuggingEnabled: false
      vnetRouteAllEnabled: true
      ipSecurityRestrictions: [for rule in ipRestrictionRules: {
        name: rule.name
        ipAddress: rule.ipAddress
        action: rule.action
        priority: rule.priority
        description: rule.description
        tag: 'Default'
      }]
      ipSecurityRestrictionsDefaultAction: 'Deny'
      scmIpSecurityRestrictionsUseMain: false
      scmIpSecurityRestrictionsDefaultAction: 'Allow'
    }
  }
}

// =============================================================================
// VNet Integration
// =============================================================================
resource vnetIntegration 'Microsoft.Web/sites/networkConfig@2024-04-01' = {
  parent: appService
  name: 'virtualNetwork'
  properties: {
    subnetResourceId: webAppSubnetId
    swiftSupported: true
  }
}

// =============================================================================
// App Service Managed Identity 加入 Entra ID Group 的權限指派
// SQL Database User 權限 (透過 App Group)
// =============================================================================
resource appServiceMiSqlRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appService.id, sqlServerId, 'MiSqlAccess')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8d6e2f3e-4cb2-4df2-b0de-1e3f5b9e8c1a') // Reader
    principalId: appService.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// 輸出
// =============================================================================
output appServiceId string = appService.id
output appServiceName string = appService.name
output appServiceDefaultHostName string = appService.properties.defaultHostName
output appServiceManagedIdentityPrincipalId string = appService.identity.principalId
output appServiceManagedIdentityTenantId string = appService.identity.tenantId
