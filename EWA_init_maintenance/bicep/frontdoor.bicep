// =============================================================================
// Azure Front Door 模組 - 辦公室 IP 白名單 + WAF
// =============================================================================

targetScope = 'resourceGroup'

@description('位置 (global for Front Door)')
param location string

@description('Front Door 名稱')
param frontDoorName string

@description('後端端點 (App Service Default Host Name)')
param backendEndpoint string

@description('Health Probe 路徑')
param probePath string = '/health'

@description('WAF Policy 名稱')
param wafPolicyName string = ''

// =============================================================================
// WAF Policy
// =============================================================================
var effectiveWafPolicyName = !empty(wafPolicyName) ? wafPolicyName : 'waf-${frontDoorName}'

// =============================================================================
// Front Door Profile
// =============================================================================
resource frontDoor 'Microsoft.Cdn/profiles@2024-05-01-preview' = {
  name: frontDoorName
  location: 'Global'
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
  properties: {}
}

// =============================================================================
// Origin Group
// =============================================================================
resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-05-01-preview' = {
  parent: frontDoor
  name: 'og-${frontDoorName}'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: probePath
      probeRequestType: 'HEAD'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 30
    }
    sessionAffinityState: 'Disabled'
  }
}

// =============================================================================
// Origin (App Service Backend)
// =============================================================================
resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2024-05-01-preview' = {
  parent: originGroup
  name: 'origin-${frontDoorName}'
  properties: {
    hostName: backendEndpoint
    httpPort: 80
    httpsPort: 443
    originHostHeader: backendEndpoint
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

// =============================================================================
// Endpoint (Route)
// =============================================================================
resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-05-01-preview' = {
  parent: frontDoor
  name: 'ep-${frontDoorName}'
  properties: {
    enabledState: 'Enabled'
  }
}

// =============================================================================
// Route
// =============================================================================
resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-05-01-preview' = {
  parent: endpoint
  name: 'route-default'
  properties: {
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: ['Http', 'Https']
    patternsToMatch: ['/*']
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
    cacheConfiguration: {
      queryStringCachingBehavior: 'IgnoreQueryString'
      compressionSettings: {
        contentTypesToCompress: ['application/json', 'text/plain']
        isCompressionEnabled: true
      }
    }
  }
}

// =============================================================================
// 輸出
// =============================================================================
output frontDoorId string = frontDoor.id
output frontDoorName string = frontDoor.name
output frontDoorEndpoint string = endpoint.properties.hostName
output frontDoorEndpointId string = endpoint.id
