// =============================================================================
// EWA Infrastructure - Main Bicep Template
// 完整 Azure 架構：App Service + SQL + Redis + Front Door + VNet + NAT Gateway
// Entra ID 驗證，無密碼/無 Key 登入，辦公室防火牆白名單
// =============================================================================

targetScope = 'subscription'

@description('部署位置')
param location string = 'japanwest'

@description('環境名稱 (e.g., production, test)')
param environment string = 'production'

@description('資源名稱前綴')
param prefix string = 'ewa'

@description('資源群組名稱')
param resourceGroupName string = 'RG_EWA_${environment}'

@description('VNet 名稱')
param vnetName string = 'vnet-${prefix}-${environment}'

@description('App Service 名稱')
param appServiceName string = '${prefix}-api-${environment}'

@description('SQL Server 名稱')
param sqlServerName string = 'sql-${prefix}-${environment}'

@description('Redis 名稱')
param redisName string = 'redis-${prefix}-${environment}'

@description('Front Door 名稱')
param frontDoorName string = 'fd-${prefix}-${environment}'

@description('Entra ID Manager Group Object ID - DB-Ewa-Prod-Manager (SQL Admin)')
param entraManagerGroupObjectId string

@description('Entra ID Reader Group Object ID - DB-Ewa-Prod-Reader (Read Only)')
param entraReaderGroupObjectId string

@description('Entra ID WebAppExecutor Group Object ID - DB-Ewa-Prod-WebAppExecutor (RW + Execute, 後端機器連線用)')
param entraWebAppExecutorGroupObjectId string

// =============================================================================
// 資源群組
// =============================================================================
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: {
    Environment: environment
    Project: prefix
    ManagedBy: 'Bicep'
  }
}

// =============================================================================
// VNet + NAT Gateway 模組
// =============================================================================
module vnetModule './vnet.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'vnet-deployment'
  params: {
    location: location
    vnetName: vnetName
    addressPrefix: '10.0.0.0/16'
    webAppSubnetPrefix: '10.0.1.0/24'
    redisSubnetPrefix: '10.0.2.0/24'
    natGatewayName: 'nat-${prefix}-${environment}'
    publicIPName: 'pip-nat-${prefix}-${environment}'
  }
}

// =============================================================================
// Azure SQL Server + Elastic Pool (DTU 50) + Database (100GB) 模組
// =============================================================================
module sqlModule './sql.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'sql-deployment'
  params: {
    location: location
    sqlServerName: sqlServerName
    databaseName: 'db-${prefix}-${environment}'
    elasticPoolName: 'ep-${prefix}-${environment}'
    elasticPoolDtu: 50
    elasticPoolEdition: 'Standard'
    databaseMaxSizeBytes: 107374182400
    entraManagerGroupObjectId: entraManagerGroupObjectId
    entraReaderGroupObjectId: entraReaderGroupObjectId
    entraWebAppExecutorGroupObjectId: entraWebAppExecutorGroupObjectId
  }
}

// =============================================================================
// Azure Redis 模組
// =============================================================================
module redisModule './redis.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'redis-deployment'
  params: {
    location: location
    redisName: redisName
    vnetId: vnetModule.outputs.vnetId
    redisSubnetId: vnetModule.outputs.redisSubnetId
    entraManagerGroupObjectId: entraManagerGroupObjectId
    entraWebAppExecutorGroupObjectId: entraWebAppExecutorGroupObjectId
  }
}

// =============================================================================
// App Service 模組
// =============================================================================
module appServiceModule './appservice.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'appservice-deployment'
  params: {
    location: location
    appServiceName: appServiceName
    appServicePlanName: 'asp-${prefix}-${environment}'
    vnetId: vnetModule.outputs.vnetId
    webAppSubnetId: vnetModule.outputs.webAppSubnetId
    sqlServerId: sqlModule.outputs.sqlServerId
    redisId: redisModule.outputs.redisId
    entraWebAppExecutorGroupObjectId: entraWebAppExecutorGroupObjectId
  }
  dependsOn: [
    vnetModule
    sqlModule
    redisModule
  ]
}

// =============================================================================
// Front Door 模組
// =============================================================================
module frontDoorModule './frontdoor.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'frontdoor-deployment'
  params: {
    location: 'global'
    frontDoorName: frontDoorName
    backendEndpoint: appServiceModule.outputs.appServiceDefaultHostName
    probePath: '/health'
  }
  dependsOn: [
    appServiceModule
  ]
}

// =============================================================================
// 輸出
// =============================================================================
output resourceGroupId string = rg.id
output resourceGroupName string = rg.name
output vnetId string = vnetModule.outputs.vnetId
output natGatewayPublicIP string = vnetModule.outputs.natGatewayPublicIP
output sqlServerFullyQualifiedDomainName string = sqlModule.outputs.sqlServerFullyQualifiedDomainName
output sqlConnectionString string = sqlModule.outputs.sqlConnectionString
output redisHostName string = redisModule.outputs.redisHostName
output redisConnectionString string = redisModule.outputs.redisConnectionString
output appServiceDefaultHostName string = appServiceModule.outputs.appServiceDefaultHostName
output appServiceManagedIdentityPrincipalId string = appServiceModule.outputs.appServiceManagedIdentityPrincipalId
output frontDoorEndpoint string = frontDoorModule.outputs.frontDoorEndpoint
