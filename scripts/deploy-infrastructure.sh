#!/bin/bash
# =============================================================================
# deploy-infrastructure.sh - EWA Infrastructure 部署腳本
# 使用 Bicep 一鍵部署完整架構
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# 變數定義
# -----------------------------------------------------------------------------
SUBSCRIPTION_ID="99804447-bee3-4371-9bd5-672a86845c40"
LOCATION="japanwest"
ENVIRONMENT="production"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_DIR="${SCRIPT_DIR}/bicep"

# Entra ID Group Object IDs (從 Portal 取得後填入)
# 三個群組：Manager / Reader / WebAppExecutor
ENTRA_MANAGER_GROUP_OBJECT_ID="${ENTRA_MANAGER_GROUP_OBJECT_ID:-your-manager-group-object-id}"
ENTRA_READER_GROUP_OBJECT_ID="${ENTRA_READER_GROUP_OBJECT_ID:-your-reader-group-object-id}"
ENTRA_WEBAPPEXECUTOR_GROUP_OBJECT_ID="${ENTRA_WEBAPPEXECUTOR_GROUP_OBJECT_ID:-your-webappexecutor-group-object-id}"

echo "=============================================="
echo " EWA Infrastructure Deployment"
echo " Environment: $ENVIRONMENT"
echo " Location: $LOCATION"
echo "=============================================="

# -----------------------------------------------------------------------------
# 步驟 1: 登入 Azure
# -----------------------------------------------------------------------------
echo ""
echo "[1/6] 登入 Azure..."
az account set --subscription "$SUBSCRIPTION_ID"
echo "  ✓ 已切換到 Subscription: $SUBSCRIPTION_ID"

# -----------------------------------------------------------------------------
# 步驟 2: 建立資源群組
# -----------------------------------------------------------------------------
echo ""
echo "[2/6] 建立資源群組 RG_EWA_${ENVIRONMENT}..."
az group create \
  --name "RG_EWA_${ENVIRONMENT}" \
  --location "$LOCATION" \
  --tags Environment="$ENVIRONMENT" ManagedBy="Bicep"

# -----------------------------------------------------------------------------
# 步驟 3: 部署 Bicep 模板
# -----------------------------------------------------------------------------
echo ""
echo "[3/6] 驗證 Bicep 模板..."
az bicep build --file "${BICEP_DIR}/main.bicep"

echo ""
echo "[4/6] 部署資源到 Azure (subscription scope)..."
az deployment sub create \
  --name "ewa-infra-$(date +%Y%m%d%H%M%S)" \
  --subscription "$SUBSCRIPTION_ID" \
  --location "$LOCATION" \
  --template-file "${BICEP_DIR}/main.bicep" \
  --parameters \
    environment="$ENVIRONMENT" \
    entraManagerGroupObjectId="$ENTRA_MANAGER_GROUP_OBJECT_ID" \
    entraReaderGroupObjectId="$ENTRA_READER_GROUP_OBJECT_ID" \
    entraWebAppExecutorGroupObjectId="$ENTRA_WEBAPPEXECUTOR_GROUP_OBJECT_ID" \
  --query "{ \
    resourceGroup: properties.outputs.resourceGroupName.value, \
    vnetId: properties.outputs.vnetId.value, \
    natIp: properties.outputs.natGatewayPublicIP.value, \
    sqlServer: properties.outputs.sqlServerFullyQualifiedDomainName.value, \
    redis: properties.outputs.redisHostName.value, \
    appService: properties.outputs.appServiceDefaultHostName.value, \
    frontDoor: properties.outputs.frontDoorEndpoint.value \
  }" \
  -o table

# -----------------------------------------------------------------------------
# 步驟 4: 設定 SQL 資料庫 Entra ID 使用者
# -----------------------------------------------------------------------------
echo ""
echo "[5/6] 設定 SQL Database Entra ID 使用者權限..."

SQL_SERVER=$(az deployment sub show \
  --name "ewa-infra-*" \
  --query "properties.outputs.sqlServerFullyQualifiedDomainName.value" \
  --subscription "$SUBSCRIPTION_ID" \
  -o tsv)

echo "  SQL Server: $SQL_SERVER"
  echo "  請手動執行以下 SQL 指令 (需要 Manager 群組的 Entra ID 身分登入):"
  echo ""
  echo "  -- Manager: Full Control (已有 Server Admin)"
  echo "  CREATE USER [DB-Ewa-Prod-Manager] FROM EXTERNAL PROVIDER;"
  echo "  ALTER ROLE db_owner ADD MEMBER [DB-Ewa-Prod-Manager];"
  echo ""
  echo "  -- WebAppExecutor: RW + Execute (給 App Service Managed Identity)"
  echo "  CREATE USER [DB-Ewa-Prod-WebAppExecutor] FROM EXTERNAL PROVIDER;"
  echo "  ALTER ROLE db_datareader ADD MEMBER [DB-Ewa-Prod-WebAppExecutor];"
  echo "  ALTER ROLE db_datawriter ADD MEMBER [DB-Ewa-Prod-WebAppExecutor];"
  echo "  GRANT EXECUTE TO [DB-Ewa-Prod-WebAppExecutor];"
  echo ""
  echo "  -- Reader: Read Only"
  echo "  CREATE USER [DB-Ewa-Prod-Reader] FROM EXTERNAL PROVIDER;"
  echo "  ALTER ROLE db_datareader ADD MEMBER [DB-Ewa-Prod-Reader];"
echo ""

# -----------------------------------------------------------------------------
# 步驟 6: 輸出部署摘要
# -----------------------------------------------------------------------------
echo ""
echo "[6/6] 取得部署輸出..."

DEPLOY_OUTPUT=$(az deployment sub show \
  --name "ewa-infra-*" \
  --subscription "$SUBSCRIPTION_ID" \
  --query "properties.outputs" \
  -o json 2>/dev/null || echo "{}")

echo ""
echo "=============================================="
echo "  部署完成！"
echo "=============================================="
echo ""
echo "資源資訊:"
echo "  VNet:           vnet-ewa-${ENVIRONMENT}"
echo "  NAT Gateway IP: $(echo "$DEPLOY_OUTPUT" | jq -r '.natGatewayPublicIP.value // "N/A"')"
echo "  SQL Server:     $(echo "$DEPLOY_OUTPUT" | jq -r '.sqlServerFullyQualifiedDomainName.value // "N/A"')"
echo "  Redis:          $(echo "$DEPLOY_OUTPUT" | jq -r '.redisHostName.value // "N/A"')"
echo "  App Service:    $(echo "$DEPLOY_OUTPUT" | jq -r '.appServiceDefaultHostName.value // "N/A"')"
echo "  Front Door:     $(echo "$DEPLOY_OUTPUT" | jq -r '.frontDoorEndpoint.value // "N/A"')"
echo ""
echo "已配置功能:"
echo "  ✓ Entra ID 驗證 (SQL + Redis)"
echo "  ✓ NAT Gateway 固定出口 IP"
echo "  ✓ VNet Integration (App Service + Redis)"
echo "  ✓ 辦公室防火牆 IP 白名單 (SQL + App Service)"
echo "  ✓ Managed Identity (無密碼登入)"
echo "  ✓ Front Door 負載平衡"
echo "  ✓ HTTPS Only / TLS 1.2"
echo ""
echo "後續手動作業:"
echo "  1. 執行 SQL Entra ID User 建立 (上方 SQL 指令)"
echo "  2. 更新 App Service Container Image"
echo "  3. 設定 Front Door 自訂網域"
echo "  4. 設定 WAF Policy 規則"
echo ""
