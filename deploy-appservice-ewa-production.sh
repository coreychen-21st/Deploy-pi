#!/bin/bash

# =============================================================================
# Azure App Service 部署腳本 - Earned Wage Access API (Production)
# 使用 AZ CLI 部署 Linux Container App Service
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# 變數定義
# -----------------------------------------------------------------------------
SUBSCRIPTION_ID="99804447-bee3-4371-9bd5-672a86845c40"
RESOURCE_GROUP="RG_Ewa_Production"
APP_NAME="ewa-internal-api-earnedwageaccess"
APP_SERVICE_PLAN="AppPlan-Prod-API-EarnedWage"
APP_SERVICE_PLAN_SKU="P0v3"
LOCATION="japanwest"
DOCKER_IMAGE=""

# VNet 整合
VNET_RESOURCE_ID="/subscriptions/99804447-bee3-4371-9bd5-672a86845c40/resourceGroups/RG_Ewa_Production/providers/Microsoft.Network/virtualNetworks/vnet-ewa/subnets/subnet_ewa_webapps"
VNET_ID="${VNET_RESOURCE_ID%/subnets/*}"
SUBNET_NAME="${VNET_RESOURCE_ID##*/subnets/}"

# App Service Plan 資源 ID
APP_SERVICE_PLAN_ID="/subscriptions/99804447-bee3-4371-9bd5-672a86845c40/resourceGroups/RG_EWA_Production/providers/Microsoft.Web/serverFarms/AppPlan-Prod-API-EarnedWage"

# -----------------------------------------------------------------------------
# 步驟 1: 設定 Subscription
# -----------------------------------------------------------------------------
echo "=== 步驟 1: 設定 Subscription ==="
az account set --subscription $SUBSCRIPTION_ID
echo "已切換到 Subscription: $SUBSCRIPTION_ID"

# -----------------------------------------------------------------------------
# 步驟 2: 確認/建立 App Service Plan (Linux)
# -----------------------------------------------------------------------------
echo ""
echo "=== 步驟 2: 確認/建立 App Service Plan ==="

if az appservice plan show --resource-group $RESOURCE_GROUP --name $APP_SERVICE_PLAN > /dev/null 2>&1; then
  echo "App Service Plan 已存在: $APP_SERVICE_PLAN"
else
  echo "App Service Plan 不存在，開始建立: $APP_SERVICE_PLAN"
  az appservice plan create \
    --resource-group $RESOURCE_GROUP \
    --name $APP_SERVICE_PLAN \
    --is-linux \
    --sku $APP_SERVICE_PLAN_SKU \
    --location $LOCATION \
    --query "id" -o tsv
  echo "App Service Plan 建立完成: $APP_SERVICE_PLAN (SKU: $APP_SERVICE_PLAN_SKU)"
fi

# -----------------------------------------------------------------------------
# 步驟 3: 建立 App Service (Linux Container)
# -----------------------------------------------------------------------------
echo ""
echo "=== 步驟 3: 建立 App Service ==="
if az webapp show --resource-group $RESOURCE_GROUP --name $APP_NAME > /dev/null 2>&1; then
  echo "App Service 已存在: $APP_NAME，略過建立"
else
  if [ -n "$DOCKER_IMAGE" ]; then
    az webapp create \
      --resource-group $RESOURCE_GROUP \
      --plan $APP_SERVICE_PLAN \
      --name $APP_NAME \
      --container-image-name "$DOCKER_IMAGE" \
      --https-only true \
      --query "id" -o tsv
  else
    az webapp create \
      --resource-group $RESOURCE_GROUP \
      --plan $APP_SERVICE_PLAN \
      --name $APP_NAME \
      --runtime "DOTNETCORE:8.0" \
      --https-only true \
      --query "id" -o tsv
    echo "未指定 DOCKER_IMAGE，先以 runtime 建立 Web App，後續可在 Portal 手動改為容器映像"
  fi
fi

echo "App Service 建立完成: $APP_NAME"

# -----------------------------------------------------------------------------
# 步驟 4: 啟用 System Assigned Managed Identity
# -----------------------------------------------------------------------------
echo ""
echo "=== 步驟 4: 啟用 System Assigned Managed Identity ==="
az webapp identity assign \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME

IDENTITY_PRINCIPAL_ID=$(az webapp identity show \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --query "principalId" -o tsv)

echo "Managed Identity 已啟用，Principal ID: $IDENTITY_PRINCIPAL_ID"

# -----------------------------------------------------------------------------
# 步驟 5: 配置 General Settings (Site Config)
# -----------------------------------------------------------------------------
echo ""
echo "=== 步驟 5: 配置 General Settings ==="

# 配置平台設定
if [ -n "$DOCKER_IMAGE" ]; then
  az webapp config set \
    --resource-group $RESOURCE_GROUP \
    --name $APP_NAME \
    --linux-fx-version "DOCKER|$DOCKER_IMAGE" \
    --always-on true \
    --http20-enabled false \
    --min-tls-version "1.2" \
    --ftps-state "FtpsOnly" \
    --use-32bit-worker-process true \
    --web-sockets-enabled false \
    --startup-file ""
else
  az webapp config set \
    --resource-group $RESOURCE_GROUP \
    --name $APP_NAME \
    --always-on true \
    --http20-enabled false \
    --min-tls-version "1.2" \
    --ftps-state "FtpsOnly" \
    --use-32bit-worker-process true \
    --web-sockets-enabled false \
    --startup-file ""
fi

# client affinity 需透過資源層更新
az resource update \
  --resource-type Microsoft.Web/sites \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --set properties.clientAffinityEnabled=false properties.clientAffinityProxyEnabled=false \
  --api-version 2024-11-01

echo "General Settings 配置完成"

# -----------------------------------------------------------------------------
# 步驟 6: 配置 IP Security Restrictions
# -----------------------------------------------------------------------------
echo ""
echo "=== 步驟 6: 配置 IP Security Restrictions ==="

# 定義 IP 限制規則 (從 Bicep 提取)
# 格式：ip_address|action|priority|name|description|tag

declare -a IP_RESTRICTIONS=(
  "218.32.244.152/32|Allow|100|樂分期 2 樓||Default"
  "210.243.135.140/32|Allow|100|Allow-IT-143-IP||Default"
  "AzureFrontDoor.Backend|Allow|100|AllowFrontDoor||ServiceTag"
  "59.124.7.175/32|Allow|101|Allow-Pi-OA||Default"
  "4.190.186.188/32|Allow|102|Allow-pitest-internal||Default"
  "125.227.46.135/31|Allow|113|office_143_2f|managed by script|Default"
  "219.70.120.125/32|Allow|123|office_143_2f|managed by script|Default"
  "210.242.238.172/32|Allow|133|office_163_2f3f5f8f10f|managed by script|Default"
  "219.86.43.106/31|Allow|143|office_143_2f3f5f8f10f|managed by script|Default"
)

# 先清除現有的 Main Site IP 限制
echo "清除現有 Main Site IP 限制..."
mapfile -t MAIN_RULES < <(az webapp config access-restriction show \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --query "ipSecurityRestrictions[].name" -o tsv 2>/dev/null || true)

for rule in "${MAIN_RULES[@]}"; do
  if [ -n "$rule" ]; then
    az webapp config access-restriction remove \
      --resource-group $RESOURCE_GROUP \
      --name $APP_NAME \
      --rule-name "$rule" || true
  fi
done

# 新增 IP 限制規則
echo "新增 IP 限制規則..."
for restriction in "${IP_RESTRICTIONS[@]}"; do
  IFS='|' read -r ip action priority name description tag <<< "$restriction"
  
  if [ "$tag" == "ServiceTag" ]; then
    echo "  新增 Service Tag 規則：$name ($ip)"
    az webapp config access-restriction add \
      --resource-group $RESOURCE_GROUP \
      --name $APP_NAME \
      --rule-name "$name" \
      --priority $priority \
      --action $action \
      --service-tag "$ip" \
      --description "$description"
  else
    echo "  新增 IP 規則：$name ($ip)"
    az webapp config access-restriction add \
      --resource-group $RESOURCE_GROUP \
      --name $APP_NAME \
      --rule-name "$name" \
      --priority $priority \
      --action $action \
      --ip-address "$ip" \
      --description "$description"
  fi
done

# 設定預設動作為 Deny
echo "設定預設動作為 Deny..."
az webapp config access-restriction set \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --default-action Deny

echo "IP Security Restrictions 配置完成"

# -----------------------------------------------------------------------------
# 步驟 7: 配置 SCM IP Restrictions (允許所有)
# -----------------------------------------------------------------------------
echo ""
echo "=== 步驟 7: 配置 SCM IP Restrictions ==="

# 清除現有 SCM Site IP 限制
mapfile -t SCM_RULES < <(az webapp config access-restriction show \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --query "scmIpSecurityRestrictions[].name" -o tsv 2>/dev/null || true)

for rule in "${SCM_RULES[@]}"; do
  if [ -n "$rule" ]; then
    az webapp config access-restriction remove \
      --resource-group $RESOURCE_GROUP \
      --name $APP_NAME \
      --rule-name "$rule" \
      --scm-site true || true
  fi
done

# SCM 允許所有存取
echo "設定 SCM 允許所有存取..."
az webapp config access-restriction set \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --use-same-restrictions-for-scm-site false \
  --scm-default-action Allow

echo "SCM IP Restrictions 配置完成"

# -----------------------------------------------------------------------------
# 步驟 8: 配置 VNet Integration
# -----------------------------------------------------------------------------
echo ""
echo "=== 步驟 8: 配置 VNet Integration ==="

az webapp vnet-integration add \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --vnet $VNET_ID \
  --subnet $SUBNET_NAME

echo "VNet Integration 配置完成：$VNET_RESOURCE_ID"

# -----------------------------------------------------------------------------
# 步驟 9: 禁用 FTP 和 SCM Publishing Credentials
# -----------------------------------------------------------------------------
echo ""
echo "=== 步驟 9: 配置 Publishing Credentials Policies ==="

echo "禁用 FTP/SCM Basic Auth Publishing Credentials..."
az webapp update \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --basic-auth Disabled > /dev/null

echo "Publishing Credentials Policies 配置完成"

# -----------------------------------------------------------------------------
# 步驟 10: 配置 Environment Variables (App Settings)
# -----------------------------------------------------------------------------
echo ""
echo "=== 步驟 10: 配置 Environment Variables ==="

# 先移除不需要的 Application Insights / DiagnosticServices 設定
az webapp config appsettings delete \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --setting-names \
    APPINSIGHTS_INSTRUMENTATIONKEY \
    APPINSIGHTS_PROFILERFEATURE_VERSION \
    APPINSIGHTS_SNAPSHOTFEATURE_VERSION \
    APPLICATIONINSIGHTS_CONFIGURATION_CONTENT \
    APPLICATIONINSIGHTS_CONNECTION_STRING \
    ApplicationInsightsAgent_EXTENSION_VERSION \
    DiagnosticServices_EXTENSION_VERSION \
    InstrumentationEngine_EXTENSION_VERSION \
    SnapshotDebugger_EXTENSION_VERSION \
    XDT_MicrosoftApplicationInsights_BaseExtensions \
    XDT_MicrosoftApplicationInsights_Mode \
    XDT_MicrosoftApplicationInsights_PreemptSdk || true

# 套用需要保留的 App Settings
az webapp config appsettings set \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --settings \
    "ASPNETCORE_ENVIRONMENT=Test" \
    "DOCKER_REGISTRY_SERVER_PASSWORD=I+nsvkXS4J6INWsVRgXkRdKPvQJvmU8cl0Lf1geMT6+ACRAQseEd" \
    "DOCKER_REGISTRY_SERVER_URL=https://acrtestpi.azurecr.io" \
    "DOCKER_REGISTRY_SERVER_USERNAME=acrtestpi" \
    "TZ=Asia/Taipei" \
    "WEBSITE_HTTPLOGGING_RETENTION_DAYS=60" \
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE=false" \
    "WEBSITES_PORT=8080"

# 設定 slot sticky settings
az webapp config appsettings set \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --slot-settings \
    "APPINSIGHTS_INSTRUMENTATIONKEY=" \
    "APPINSIGHTS_PROFILERFEATURE_VERSION=" \
    "APPINSIGHTS_SNAPSHOTFEATURE_VERSION=" \
    "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT=" \
    "ApplicationInsightsAgent_EXTENSION_VERSION=" \
    "DiagnosticServices_EXTENSION_VERSION=" \
    "InstrumentationEngine_EXTENSION_VERSION=" \
    "SnapshotDebugger_EXTENSION_VERSION=" \
    "XDT_MicrosoftApplicationInsights_BaseExtensions=" \
    "XDT_MicrosoftApplicationInsights_Mode=" \
    "XDT_MicrosoftApplicationInsights_PreemptSdk=" || true

# 清除剛才為了 sticky 屬性建立的空值 keys
az webapp config appsettings delete \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --setting-names \
    APPINSIGHTS_INSTRUMENTATIONKEY \
    APPINSIGHTS_PROFILERFEATURE_VERSION \
    APPINSIGHTS_SNAPSHOTFEATURE_VERSION \
    APPLICATIONINSIGHTS_CONFIGURATION_CONTENT \
    ApplicationInsightsAgent_EXTENSION_VERSION \
    DiagnosticServices_EXTENSION_VERSION \
    InstrumentationEngine_EXTENSION_VERSION \
    SnapshotDebugger_EXTENSION_VERSION \
    XDT_MicrosoftApplicationInsights_BaseExtensions \
    XDT_MicrosoftApplicationInsights_Mode \
    XDT_MicrosoftApplicationInsights_PreemptSdk || true

echo "Environment Variables 配置完成"
echo "已移除 Application Insights / DiagnosticServices 設定，其他來源設定已保留"

# -----------------------------------------------------------------------------
# 步驟 11: 配置其他應用設定
# -----------------------------------------------------------------------------
echo ""
echo "=== 步驟 11: 配置其他應用設定 ==="

echo "配置 web server logging (http logging)..."
az webapp log config \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --web-server-logging filesystem

echo "配置 detailed error messages / failed request tracing..."
az webapp log config \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --detailed-error-messages false \
  --failed-request-tracing false

echo "配置 remote debugging..."
az webapp config set \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --remote-debugging-enabled false

echo "其他應用設定配置完成"

# -----------------------------------------------------------------------------
# 步驟 12: 配置 Outbound VNet Routing
# -----------------------------------------------------------------------------
echo ""
echo "=== 步驟 12: 配置 Outbound VNet Routing ==="

# 配置 VNet Route All Enabled (讓所有流量通過 VNet)
az webapp config set \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --vnet-route-all-enabled true

echo "Outbound VNet Routing 配置完成"

# -----------------------------------------------------------------------------
# 步驟 13: 重啟 App Service
# -----------------------------------------------------------------------------
echo ""
echo "=== 步驟 13: 重啟 App Service ==="

az webapp restart \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME

echo "App Service 已重啟"

# -----------------------------------------------------------------------------
# 完成
# -----------------------------------------------------------------------------
echo ""
echo "============================================================================="
echo "部署完成！"
echo "============================================================================="
echo ""
echo "App Service 資訊:"
echo "  名稱：$APP_NAME"
echo "  資源群組：$RESOURCE_GROUP"
echo "  位置：$LOCATION"
echo "  App Service Plan: $APP_SERVICE_PLAN"
if [ -n "$DOCKER_IMAGE" ]; then
  echo "  Docker Image: $DOCKER_IMAGE"
else
  echo "  Docker Image: (未設定，請後續手動設定)"
fi
echo "  URL: https://$APP_NAME.azurewebsites.net"
echo ""
echo "已配置項目:"
echo "  ✓ System Assigned Managed Identity"
echo "  ✓ VNet Integration (vnet-ewa/subnet_prod_webapps)"
echo "  ✓ IP Security Restrictions (19 條規則)"
echo "  ✓ HTTPS Only"
echo "  ✓ FTPS Only"
echo "  ✓ Always On"
echo "  ✓ TLS 1.2"
echo "  ✓ Publishing Credentials (FTP/SCM) 已禁用"
echo ""
echo "後續手動作業:"
echo "  1. 建立 preview deployment slot (如需)"
echo "  2. 確認正式 container image 後再設定"
echo "  3. 驗證 Docker Container 啟動狀態"
echo "  4. 測試 VNet 連線性"
echo ""
echo "============================================================================="
