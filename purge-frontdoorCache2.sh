#!/bin/bash
set -e

# Azure Front Door Premium - Purge CDN Cache Script
# 清除 Front Door CDN Cache

# ==========================================
# 配置變量
# ==========================================
RESOURCE_GROUP="AzureFrontDoorRG"
FRONT_DOOR_NAME="21CTAzureFrontDoor"
SUBSCRIPTION_ID="c9f80f0b-7d34-4410-a79c-ca23fb550d20"

ENDPOINT_PRODUCTION="endpoint-production"
ENDPOINT_TEST="endpoint-test"

DOMAIN_PRODUCTION=""             # 若有正式 domain 填入
DOMAIN_TEST="test-internal.sofa-pay.com"

# ==========================================
# 使用說明
# ==========================================
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -e, --env     環境選擇: test | production | all  (預設: test)"
  echo "  -p, --path    指定清除路徑, 例如: /images/*      (預設: /* 清除全部)"
  echo "  -h, --help    顯示說明"
  echo ""
  echo "Examples:"
  echo "  $0 -e test                  # 清除 test 環境全部 cache"
  echo "  $0 -e production            # 清除 production 環境全部 cache"
  echo "  $0 -e all                   # 清除所有環境 cache"
  echo "  $0 -e test -p /api/*        # 清除 test 環境 /api/* 路徑"
  exit 0
}

# ==========================================
# 預設參數
# ==========================================
ENV="test"
PATH_TO_PURGE="/*"

while [[ $# -gt 0 ]]; do
  case $1 in
    -e|--env)
      ENV="$2"
      shift 2
      ;;
    -p|--path)
      PATH_TO_PURGE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "未知參數: $1"
      usage
      ;;
  esac
done

# ==========================================
# 函式：清除指定 endpoint cache
# ==========================================
purge_cache() {
  local ENDPOINT=$1
  local DOMAIN=$2

  echo "------------------------------------------"
  echo "清除 Endpoint : $ENDPOINT"
  echo "Domain        : ${DOMAIN:-(所有 domain)}"
  echo "路徑           : $PATH_TO_PURGE"
  echo "------------------------------------------"

  az afd endpoint purge \
    --resource-group "$RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_NAME" \
    --endpoint-name "$ENDPOINT" \
    --content-paths "$PATH_TO_PURGE" \
    --domains "$DOMAIN"

  echo "✓ Cache 清除完成: $ENDPOINT"
  echo ""
}

# ==========================================
# 主流程
# ==========================================
echo "=========================================="
echo "Azure Front Door - Purge CDN Cache"
echo "=========================================="
echo "環境   : $ENV"
echo "路徑   : $PATH_TO_PURGE"
echo ""

az account set --subscription "$SUBSCRIPTION_ID"
echo "✓ 已切換到 Subscription: $SUBSCRIPTION_ID"
echo ""

case $ENV in
  test)
    purge_cache "$ENDPOINT_TEST" "$DOMAIN_TEST"
    ;;
  production)
    purge_cache "$ENDPOINT_PRODUCTION" "$DOMAIN_PRODUCTION"
    ;;
  all)
    purge_cache "$ENDPOINT_TEST" "$DOMAIN_TEST"
    purge_cache "$ENDPOINT_PRODUCTION" "$DOMAIN_PRODUCTION"
    ;;
  *)
    echo "錯誤: 未知環境 '$ENV'，請使用 test | production | all"
    exit 1
    ;;
esac

echo "=========================================="
echo "所有 Cache 清除完成！"
echo "注意: Front Door 設定更新最長需要 20 分鐘生效"
echo "=========================================="
