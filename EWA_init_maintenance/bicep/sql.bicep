// =============================================================================
// Azure SQL Server + Elastic Pool (DTU 50) + Database (100GB Max)
// 辦公室防火牆白名單 + Entra ID 驗證
// 初期標準規格，上線後再依需求調整大小
// =============================================================================

targetScope = 'resourceGroup'

@description('位置')
param location string

@description('SQL Server 名稱')
param sqlServerName string

@description('Database 名稱')
param databaseName string

@description('Elastic Pool 名稱')
param elasticPoolName string = 'ep-${sqlServerName}'

@description('Entra ID Manager Group Object ID - DB-Ewa-Prod-Manager (SQL Server Admin)')
param entraManagerGroupObjectId string

@description('Entra ID Reader Group Object ID - DB-Ewa-Prod-Reader (Read Only)')
param entraReaderGroupObjectId string

@description('Entra ID WebAppExecutor Group Object ID - DB-Ewa-Prod-WebAppExecutor (RW + Execute)')
param entraWebAppExecutorGroupObjectId string

@description('SQL Server Admin Login (僅建立時需要，後續使用 Entra ID)')
@secure()
param administratorLogin string = 'sqladmin_do_not_use'

@description('SQL Server Admin Password (僅建立時需要，後續使用 Entra ID)')
@secure()
param administratorLoginPassword string = ''

@description('Elastic Pool DTU (初始 50，後續可調)')
param elasticPoolDtu int = 50

@description('Elastic Pool Edition (Standard/Basic/Premium)')
param elasticPoolEdition string = 'Standard'

@description('Database 最大大小 (GB)，初始 100GB，後續可調')
param databaseMaxSizeBytes int = 107374182400

@description('Database 備份備援')
param backupStorageRedundancy string = 'Geo'

// =============================================================================
// 辦公室防火牆白名單
// =============================================================================
var officeFirewallRules = [
  {
    name: 'Office_2F'
    startIpAddress: '218.32.244.152'
    endIpAddress: '218.32.244.152'
  }
  {
    name: 'IT_143_IP'
    startIpAddress: '210.243.135.140'
    endIpAddress: '210.243.135.140'
  }
  {
    name: 'Pi_OA_IP'
    startIpAddress: '59.124.7.175'
    endIpAddress: '59.124.7.175'
  }
  {
    name: 'Pitest_Internal'
    startIpAddress: '4.190.186.188'
    endIpAddress: '4.190.186.188'
  }
  {
    name: 'Office_143_2F_1'
    startIpAddress: '125.227.46.135'
    endIpAddress: '125.227.46.136'
  }
  {
    name: 'Office_143_2F_2'
    startIpAddress: '219.70.120.125'
    endIpAddress: '219.70.120.125'
  }
  {
    name: 'Office_163_2F3F5F8F10F'
    startIpAddress: '210.242.238.172'
    endIpAddress: '210.242.238.172'
  }
  {
    name: 'Office_143_2F3F5F8F10F'
    startIpAddress: '219.86.43.106'
    endIpAddress: '219.86.43.107'
  }
]

// =============================================================================
// SQL Server (使用 Entra ID Authentication Only)
// =============================================================================
resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: sqlServerName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: ''
    administrators: {
      administratorType: 'ActiveDirectory'
      login: 'DB-Ewa-Prod-Manager'
      sid: entraManagerGroupObjectId
      tenantId: subscription().tenantId
      azureADOnlyAuthentication: true
    }
    publicNetworkAccess: 'Enabled'
    minimalTlsVersion: '1.2'
  }
  tags: {
    AuthMethod: 'EntraID'
    NoPassword: 'true'
  }
}

// =============================================================================
// 辦公室防火牆規則
// =============================================================================
resource officeFwRules 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = [for rule in officeFirewallRules: {
  parent: sqlServer
  name: rule.name
  properties: {
    startIpAddress: rule.startIpAddress
    endIpAddress: rule.endIpAddress
  }
}]

// =============================================================================
// Azure 服務可連線防火牆規則
// =============================================================================
resource allowAzureServices 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// =============================================================================
// Elastic Pool (DTU 50 初始，上線後再調整)
// =============================================================================
resource elasticPool 'Microsoft.Sql/servers/elasticPools@2023-05-01-preview' = {
  parent: sqlServer
  name: elasticPoolName
  location: location
  sku: {
    name: elasticPoolEdition
    tier: elasticPoolEdition
    capacity: elasticPoolDtu
  }
  properties: {
    maxSizeBytes: 107374182400
    perDatabaseSettings: {
      minCapacity: 0
      maxCapacity: elasticPoolDtu
    }
    zoneRedundant: false
  }
}

// =============================================================================
// SQL Database (放入 Elastic Pool，最大 100GB)
// =============================================================================
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  properties: {
    elasticPoolId: elasticPool.id
    maxSizeBytes: databaseMaxSizeBytes
    zoneRedundant: false
    backupStorageRedundancy: backupStorageRedundancy
  }
}

// =============================================================================
// 輸出
// =============================================================================
output sqlServerId string = sqlServer.id
output sqlServerName string = sqlServer.name
output sqlServerFullyQualifiedDomainName string = sqlServer.properties.fullyQualifiedDomainName
output elasticPoolId string = elasticPool.id
output elasticPoolName string = elasticPool.name
output elasticPoolDtu int = elasticPool.sku.capacity
output sqlDatabaseId string = sqlDatabase.id
output sqlDatabaseName string = sqlDatabase.name
output sqlDatabaseMaxSizeGB int = databaseMaxSizeBytes / 1073741824
output sqlConnectionString string = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Database=${databaseName};Authentication=Active Directory Managed Identity;'
