// =============================================================================
// Azure Managed Redis Enterprise + Entra ID 驗證
// 無密碼 / 無 Access Key 登入
// =============================================================================

targetScope = 'resourceGroup'

@description('位置')
param location string

@description('Redis 名稱')
param redisName string

@description('VNet Resource ID')
param vnetId string

@description('Redis Subnet Resource ID')
param redisSubnetId string

@description('Entra ID Manager Group Object ID - DB-Ewa-Prod-Manager (Redis Admin)')
param entraManagerGroupObjectId string

@description('Entra ID WebAppExecutor Group Object ID - DB-Ewa-Prod-WebAppExecutor (Redis User)')
param entraWebAppExecutorGroupObjectId string

@description('Redis SKU 名稱')
param redisSkuName string = 'Enterprise_E10'

@description('Redis 容量 (GB)')
param redisCapacity int = 12

// =============================================================================
// Azure Managed Redis Enterprise
// =============================================================================
resource redis 'Microsoft.Cache/redisEnterprise@2024-02-01' = {
  name: redisName
  location: location
  sku: {
    name: redisSkuName
    capacity: redisCapacity
  }
  properties: {
    minimumTlsVersion: '1.2'
    disableAccessKeyAuthentication: true
  }
}

// =============================================================================
// Redis Enterprise Database
// =============================================================================
resource redisDatabase 'Microsoft.Cache/redisEnterprise/databases@2024-02-01' = {
  parent: redis
  name: 'default'
  properties: {
    clientProtocol: 'Encrypted'
    port: 10000
    clusteringPolicy: 'OSSCluster'
    evictionPolicy: 'VolatileLRU'
  }
}

// =============================================================================
// Entra ID 權限指派
// =============================================================================

// WebAppExecutor Group → Redis Cache User (RW)
resource redisRoleWebApp 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(redis.id, entraWebAppExecutorGroupObjectId, 'RedisCacheUser')
  scope: redis
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e0f68234-74aa-48ed-b826-c38b57376e17')
    principalId: entraWebAppExecutorGroupObjectId
    principalType: 'Group'
  }
}

// Manager Group → Redis Contributor (Admin)
resource redisRoleManager 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(redis.id, entraManagerGroupObjectId, 'RedisContributor')
  scope: redis
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e0f68234-74aa-48ed-b826-c38b57376e17')
    principalId: entraManagerGroupObjectId
    principalType: 'Group'
  }
}

// =============================================================================
// 輸出
// =============================================================================
output redisId string = redis.id
output redisName string = redis.name
output redisHostName string = redis.properties.hostName
output redisPort int = 10000
output redisConnectionString string = '${redis.properties.hostName}:10000,ssl=True,abortConnect=False'
