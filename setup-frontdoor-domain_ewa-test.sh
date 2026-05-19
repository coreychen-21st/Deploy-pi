#!/bin/bash
set -e

# Azure Front Door Premium Domain Setup Script
# 快速設定新 domain 及相關資源

# 配置變量
RESOURCE_GROUP="RG_Production"
FRONT_DOOR_NAME="pifrontdoor"
SUBSCRIPTION_ID="99804447-bee3-4371-9bd5-672a86845c40"

# 新 domain 配置
ORIGIN_GROUP_NAME="origingroup-test-ewa-admin"
ORIGIN_HOSTNAME="test-ewa.azurewebsites.net"
CUSTOM_DOMAIN_NAME="test-admin.ewa.tw"
ROUTE_NAME="Route-Test-ewa-admin"

#ORIGIN_GROUP_NAME="origingroup-test-ewa-partner"
#CUSTOM_DOMAIN_NAME="test-partner.ewa.tw"
#ROUTE_NAME="Route-Test-ewa-partner"

#ORIGIN_GROUP_NAME="origingroup-test-ewa-partner-staff"
#CUSTOM_DOMAIN_NAME="test-partner-staff.ewa.tw"
#ROUTE_NAME="Route-Test-ewa-partner-staff"
ENDPOINT_NAME="endpoint-test"
CUSTOM_DOMAIN_RESOURCE_NAME=$(echo $CUSTOM_DOMAIN_NAME | tr '.' '-')

echo "=========================================="
echo "Azure Front Door Premium - Domain Setup"
echo "=========================================="
echo ""

# 1. 切換到正確的 subscription
echo "步驟 1: 切換到 subscription..."
az account set --subscription $SUBSCRIPTION_ID
echo "✓ 已切換到 Subscription: $SUBSCRIPTION_ID"
echo ""

# 2. 建立 Origin Group
echo "步驟 2: 建立 Origin Group: $ORIGIN_GROUP_NAME"
az afd origin-group create \
    --resource-group $RESOURCE_GROUP \
    --profile-name $FRONT_DOOR_NAME \
    --origin-group-name $ORIGIN_GROUP_NAME \
    --sample-size 4 \
    --successful-samples-required 3
echo "✓ Origin Group 建立完成"
echo ""

# 3. 建立 Origin
echo "步驟 3: 建立 Origin..."
az afd origin create \
    --resource-group $RESOURCE_GROUP \
    --profile-name $FRONT_DOOR_NAME \
    --origin-group-name $ORIGIN_GROUP_NAME \
    --origin-name "$ORIGIN_GROUP_NAME-Origin" \
    --host-name $ORIGIN_HOSTNAME \
    --origin-host-header $ORIGIN_HOSTNAME \
    --http-port 80 \
    --https-port 443 \
    --priority 1 \
    --weight 1000
echo "✓ Origin 建立完成"
echo ""

# 4. 建立 Custom Domain
echo "步驟 4: 建立 Custom Domain: $CUSTOM_DOMAIN_NAME"
az afd custom-domain create \
    --resource-group $RESOURCE_GROUP \
    --profile-name $FRONT_DOOR_NAME \
    --custom-domain-name "$CUSTOM_DOMAIN_RESOURCE_NAME" \
    --host-name $CUSTOM_DOMAIN_NAME
echo "✓ Custom Domain 建立完成"
echo ""

# 5. 建立 Route
echo "步驟 5: 建立 Route: $ROUTE_NAME"
az afd route create \
    --resource-group $RESOURCE_GROUP \
    --profile-name $FRONT_DOOR_NAME \
    --endpoint-name $ENDPOINT_NAME \
    --route-name $ROUTE_NAME \
    --origin-group $ORIGIN_GROUP_NAME \
    --custom-domains $CUSTOM_DOMAIN_RESOURCE_NAME \
    --patterns-to-match "/*" \
    --forwarding-protocol "HttpsOnly" \
    --link-to-default-domain "disabled" \
    --https-redirect "Disabled"
#    --link-to-default-domain "Enabled" \
#    --forwarding-protocol "MatchRequest" \
echo "✓ Route 建立完成"
echo ""

# 6. 顯示設定結果
echo "=========================================="
echo "設定完成！資源摘要:"
echo "=========================================="
echo "Origin Group: $ORIGIN_GROUP_NAME"
echo "Origin Hostname: $ORIGIN_HOSTNAME"
echo "Custom Domain: $CUSTOM_DOMAIN_NAME"
echo "Route: $ROUTE_NAME"
echo "Endpoint: $ENDPOINT_NAME.z01.azurefd.net"
echo ""
echo "下一步操作:"
echo "1. 在 DNS 提供商處新增 CNAME 紀錄:"
echo "   CNAME: $CUSTOM_DOMAIN_NAME -> $ENDPOINT_NAME.z01.azurefd.net"
echo ""
echo "2. 等待 DNS 傳播後，執行 domain 驗證:"
#echo "   az afd custom-domain show --resource-group $RESOURCE_GROUP --endpoint-name $FRONT_DOOR_NAME --custom-domain-name $CUSTOM_DOMAIN_NAME"
echo "az afd custom-domain show \
    --resource-group $RESOURCE_GROUP \
    --profile-name $FRONT_DOOR_NAME \
    --custom-domain-name $CUSTOM_DOMAIN_NAME \
    --query "{HostName:hostName, ValidationState:domainValidationState, TxtRecord:validationProperties}" \
    --output json"
echo ""
