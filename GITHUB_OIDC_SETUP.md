# GitHub OIDC 串接 Azure 完整設定教學

## 概述

GitHub Actions 透過 OIDC (OpenID Connect) 直接與 Azure 驗證，不需要在 GitHub Secrets 中存放密碼或憑證。

---

## 步驟 1：Azure 端 — 建立 App Registration 與 Federated Credential

### 1.1 建立 Azure AD Application

```powershell
# 登入 Azure
az login

# 建立 App Registration
az ad app create --display-name "github-actions-deploy-pi"
```

記下輸出中的 `appId`（即 AZURE_CLIENT_ID）。

### 1.2 建立 Service Principal

```powershell
$APP_ID = "你的-appId"

az ad sp create --id $APP_ID
```

### 1.3 授予 Service Principal RBAC 權限

```powershell
$SP_OBJECT_ID = (az ad sp show --id $APP_ID --query id -o tsv)
$SUB_ID = "你的-subscription-id"

# 授予 Contributor role（針對特定 subscription）
az role assignment create \
  --assignee $SP_OBJECT_ID \
  --role Contributor \
  --scope "/subscriptions/$SUB_ID"
```

> 💡 若需要跨多個 subscription 操作，需對每個 subscription 重複執行 role assignment。

### 1.4 建立 OIDC Federated Credential

在 Azure Portal → App registrations → `github-actions-deploy-pi` → Certificates & secrets → Federated credentials → **Add credential**

| 欄位 | 值 |
|------|-----|
| Federation scenario | GitHub Actions deploying Azure resources |
| Organization | `coreychen-21st` |
| Repository | `Deploy-pi` |
| Entity type | Branch |
| Branch name | `main` |
| Name | `deploy-pi-main` |

或用 CLI：

```powershell
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "deploy-pi-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:coreychen-21st/Deploy-pi:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

---

## 步驟 2：GitHub 端 — 設定 Secrets + Variables

前往 repo Settings → Secrets and variables → Actions → **New repository secret**，新增以下 3 個 secrets：

### 必要 Secrets (app-ops.yml / deploy-infrastructure.yml 共用)

| Secret Name | 值 | 從哪裡取得 |
|-------------|-----|------------|
| `AZURE_CLIENT_ID` | App Registration 的 `appId` | 步驟 1.1 |
| `AZURE_TENANT_ID` | Azure AD tenant ID | `az account show --query tenantId -o tsv` |
| `AZURE_SUBSCRIPTION_ID` | 主要 Azure subscription ID | `az account show --query id -o tsv` |

### 額外 Secrets (deploy-infrastructure.yml 專用)

| Secret Name | 用途 |
|-------------|------|
| `ENTRA_MANAGER_GROUP_OBJECT_ID` | Entra ID Manager 群組 Object ID |
| `ENTRA_READER_GROUP_OBJECT_ID` | Entra ID Reader 群組 Object ID |
| `ENTRA_WEBAPPEXECUTOR_GROUP_OBJECT_ID` | Entra ID WebApp Executor 群組 Object ID |

---

## 步驟 3：GitHub 端 — 建立 Deployment Environments

GitHub repo Settings → Environments → **New environment**，建立兩個環境：

### `production`
- Required reviewers：可設保護
- Deployment branches：`main`

### `staging`
- Required reviewers：可無
- Deployment branches：`main`

> 這對應 `deploy-infrastructure.yml` 中的 `environment: name` 欄位。

---

## 步驟 4：驗證

### 4.1 測試 App Clone Batch

1. GitHub Repo → Actions → **App Clone Batch**
2. Run workflow，參數：
   - `environment`: `dev`
   - `location`: `Japan West`
   - `dry_run`: ✅ true
   - `action`: `clone`
   - `batch_spec`: 貼入 `batch_spec_sample.json` 內容
3. 確認 dry run 輸出無誤

### 4.2 測試 Deploy Infrastructure

1. Push 任意變更到 `bicep/**` 路徑
2. 或在 Actions → **Deploy EWA Infrastructure** → Run workflow

---

## 架構總覽

```
┌─────────────────────────────┐
│   GitHub Actions Workflow   │
│                             │
│  uses: azure/login@v2       │
│  with:                      │
│    client-id:  ${{ secrets  │
│      .AZURE_CLIENT_ID }}    │
│    tenant-id:  ${{ secrets  │
│      .AZURE_TENANT_ID }}    │
└──────────┬──────────────────┘
           │ OIDC Token Exchange
           ▼
┌─────────────────────────────┐
│      Azure AD               │
│                             │
│  App Registration           │
│  Federated Credential:      │
│  repo:xxx:ref:refs/heads/   │
│  main                       │
└──────────┬──────────────────┘
           │ Issued Access Token
           ▼
┌─────────────────────────────┐
│   Azure Subscription        │
│                             │
│  RBAC: Contributor role     │
│  assigned to Service        │
│  Principal                  │
└─────────────────────────────┘
```
