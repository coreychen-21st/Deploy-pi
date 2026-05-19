# EWA Infrastructure Architecture Document

## Overview

EWA (Earned Wage Access) Platform 完整 Azure 基礎架構，採用 **Entra ID (Azure AD) Authentication** 無密碼/無 Key 登入，搭配 **NAT Gateway 固定出口 IP**，**VNet Integration** 網路隔離。

---

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                                 Internet Users                                     │
└────────────────────────────────┬─────────────────────────────────────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    │    Azure Front Door     │
                    │    (fd-ewa-prod)        │
                    │  ┌────────────────────┐ │
                    │  │ WAF Policy         │ │
                    │  │ SSL Termination    │ │
                    │  │ Global LB          │ │
                    │  │ Route: /* → Origin │ │
                    │  │ HTTPS Redirect     │ │
                    │  │ Caching: JSON/TXT  │ │
                    │  └────────────────────┘ │
                    └────────────┬────────────┘
                                 │
                                 │ IP Restrictions:
                                 │ ✓ Allow: AzureFrontDoor.Backend (Service Tag)
                                 │ ✓ Allow: Office IPs (8 rules)
                                 │ ✓ Default Action: Deny
                                 │
                    ┌────────────┴────────────┐
                    │    App Service          │
                    │    (ewa-api-prod)       │
                    │  ┌────────────────────┐ │
                    │  │ .NET 8 / Docker    │ │
                    │  │ Managed Identity   │ │
                    │  │ Always On          │ │
                    │  │ HTTPS Only         │ │
                    │  │ TLS 1.2            │ │
                    │  │ FTPS Only          │ │
                    │  │ Route All: Enabled │ │
                    │  └────────────────────┘ │
                    └────────┬───────┬────────┘
                             │       │
              VNet Integration│       │ Outbound via VNet
                             │       │
┌────────────────────────────┼───────┼────────────────────────────────────────────┐
│                    Virtual Network (vnet-ewa-prod)  10.0.0.0/16                  │
│                                                                                  │
│  ┌─────────────────────────────────┐   ┌─────────────────────────────────┐     │
│  │ subnet-webapp (10.0.1.0/24)     │   │ subnet-redis (10.0.2.0/24)      │     │
│  │ Delegation: Microsoft.Web       │   │                                 │     │
│  │ NAT Gateway: nat-ewa-prod      │   │  ┌──────────────────────────┐   │     │
│  └─────────────────────────────────┘   │  │ Azure Managed Redis     │   │     │
│                                        │  │ (redis-ewa-prod)        │   │     │
│                                        │  │ Enterprise E10          │   │     │
│                                        │  │ DisableAccessKey: true  │   │     │
│                                        │  │ TLS 1.2                 │   │     │
│                                        │  │ Port: 10000 (Encrypted) │   │     │
│                                        │  └──────────────────────────┘   │     │
│                                        └─────────────────────────────────┘     │
│                                                     │                           │
│  ┌──────────────────────────────────────────────────┼───────────────────────┐  │
│  │                    NAT Gateway (nat-ewa-prod)     │                       │  │
│  │                    Public IP: <STATIC_IP>         │                       │  │
│  └──────────────────────────────────────────────────┼───────────────────────┘  │
│                                                     │                           │
└─────────────────────────────────────────────────────┼───────────────────────────┘
                                                      │
                                                      │ 固定出口 IP
                                                      ▼
                                       ┌────────────────────────────────┐
                                       │    Azure SQL Server            │
                                       │    (sql-ewa-prod)              │
                                       │  ┌────────────────────────────┐│
                                       │  │ Elastic Pool (Standard)    ││
                                       │  │ (ep-ewa-prod)              ││
                                       │  │ DTU 50 (初始)               ││
                                       │  │ Max: 100GB per DB           ││
                                       │  │ ┌────────────────────────┐ ││
                                       │  │ │ SQL Database           │ ││
                                       │  │ │ (db-ewa-prod)          │ ││
                                       │  │ │ Max Size: 100GB        │ ││
                                       │  │ │ Geo Backup             │ ││
                                       │  │ └────────────────────────┘ ││
                                       │  └────────────────────────────┘│
                                       │  Firewall:                     │
                                       │  ✓ Office IPs (8 rules)       │
                                       │  ✓ Allow Azure Services       │
                                       │  ✓ AzureADOnly: true          │
                                       └────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────────┐
│                              Entra ID (Azure AD)                                  │
│                                                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐ │
│  │ DB-Ewa-Prod-Manager (Server Admin)   DB-Ewa-Prod-WebAppExecutor   DB-Ewa-Prod   │ │
│  │ ┌───────────────┐ ┌───────────────┐  ┌─────────────────────────┐ │ Reader       │ │
│  │ │ RW + DDL      │ │ EXECUTE       │  │ RW + DDL + EXECUTE      │ │ (Read Only)  │ │
│  │ │ db_datareader │ │ + Type Perms  │  │ db_datareader           │ │ db_datareader│ │
│  │ │ db_datawriter │ │ StringCont..  │  │ db_datawriter           │ │              │ │
│  │ │ db_ddladmin   │ │ IntCont..     │  │ db_ddladmin             │ │              │ │
│  │ └───────────────┘ └───────────────┘  │ GRANT EXECUTE           │ │              │ │
│  │  Redis: Cache User                   │ StringContainerType     │ │              │ │
│  │                                      │ IntContainerType        │ │              │ │
│  │                                      └─────────────────────────┘ │              │ │
│  │                                      Redis: Cache User           │              │ │
│  └─────────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                   │
│                    ┌───────────────────────────┐                                  │
│                    │ App Service Managed       │                                  │
│                    │ Identity (System-Assigned) │                                  │
│                    │  ∈ WebAppExecutor Group   │                                  │
│                    │  - Token-based Auth        │                                  │
│                    │  - No Password / No Key    │                                  │
│                    └───────────────────────────┘                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## Resource Inventory

### Resource Group: `RG_EWA_Production`
### Location: `japanwest`

| Category | Resource Name | Type | SKU / Tier | Details |
|----------|--------------|------|-----------|---------|
| **VNet** | `vnet-ewa-prod` | Virtual Network | - | 10.0.0.0/16 |
| **Subnet** | `subnet-webapp` | Subnet | - | 10.0.1.0/24, Delegation: Microsoft.Web |
| **Subnet** | `subnet-redis` | Subnet | - | 10.0.2.0/24 |
| **NAT** | `nat-ewa-prod` | NAT Gateway | Standard | Static Outbound IP |
| **Public IP** | `pip-nat-ewa-prod` | Public IP | Standard | Static, NAT Gateway attached |
| **SQL** | `sql-ewa-prod` | SQL Server | - | Entra ID Only, AzureADOnly: true |
| **Elastic Pool** | `ep-ewa-prod` | Elastic Pool | Standard (DTU 50) | 100GB Max, Per-DB Settings: 0~50 DTU |
| **SQL DB** | `db-ewa-prod` | SQL Database | (In Elastic Pool) | Max 100GB, Geo Backup |
| **Redis** | `redis-ewa-prod` | Redis Enterprise | Enterprise_E10 | 12GB, DisableAccessKey: true |
| **App Plan** | `asp-ewa-prod` | App Service Plan | P0v3 | Linux, 1 instance |
| **App** | `ewa-api-prod` | Web App | - | Linux, .NET 8 / Docker |
| **Front Door** | `fd-ewa-prod` | Front Door | Standard | Global, WAF enabled |

---

## IP Whitelist (Firewall Rules)

### Common Office IP Rules (Applied to SQL Server + App Service)

| # | IP Range | Name | Description |
|---|----------|------|-------------|
| 1 | `218.32.244.152/32` | Office_2F | 樂分期 2 樓 |
| 2 | `210.243.135.140/32` | IT_143_IP | Allow-IT-143-IP |
| 3 | `59.124.7.175/32` | Pi_OA | Allow-Pi-OA |
| 4 | `4.190.186.188/32` | Pitest_Internal | Allow-pitest-internal |
| 5 | `125.227.46.135/31` | Office_143_2F_Range1 | office_143_2f |
| 6 | `219.70.120.125/32` | Office_143_2F_Range2 | office_143_2f |
| 7 | `210.242.238.172/32` | Office_163 | office_163_2f3f5f8f10f |
| 8 | `219.86.43.106/31` | Office_143_All | office_143_2f3f5f8f10f |

### App Service Specific Rules

| # | Rule | Type | Description |
|---|------|------|-------------|
| 9 | `AzureFrontDoor.Backend` | Service Tag | 允許 Front Door Backend 流量 |

---

## Authentication Flow

### No Password / No Key Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  App Service │     │  Azure AD    │     │  Target      │
│  (MI)        │     │              │     │  Resource    │
└──────┬───────┘     └──────┬───────┘     └──────┬───────┘
       │                    │                    │
       │ 1. Request Token   │                    │
       │───────────────────►│                    │
       │                    │                    │
       │ 2. Return JWT      │                    │
       │◄───────────────────│                    │
       │                    │                    │
       │ 3. Connect with Token (no password)    │
       │───────────────────────────────────────►│
       │                    │                    │
       │ 4. Authenticated   │                    │
       │◄───────────────────────────────────────│
       │                    │                    │
```

### SQL Server
- Authentication: `Active Directory Managed Identity`
- No SQL Login/Password required
- App Service Managed Identity → Entra ID Token → SQL Server

### Redis
- `disableAccessKeyAuthentication: true` (完全禁用 Access Key)
- Authentication: Entra ID Token via `DefaultAzureCredential`
- Token passed as `Password` parameter to StackExchange.Redis
- Token auto-refresh every 1 hour

---

## Network Architecture

### Outbound Traffic Flow

```
App Service Outbound
        │
        ▼
VNet Integration (subnet-webapp)
        │
        ▼
NAT Gateway (Static Public IP)
        │
        ▼
Internet / External Services
```

### Inbound Traffic Flow

```
Internet
    │
    ▼
Front Door (WAF + SSL)
    │
    ▼
App Service (IP Whitelist: Front Door Backend + Office IPs)
    │
    ▼
    ├──► SQL Server (Entra ID Token)
    │
    └──► Redis (Entra ID Token)
```

### Key Network Features
- **VNet Route All**: Enabled (all outbound traffic through VNet)
- **NAT Gateway**: Standard SKU with Static Public IP
- **VNet Integration**: Regional VNet Integration (not Gateway-required)
- **No Private Link**: Public endpoints with firewall/IP restrictions

---

## Deployment

### Prerequisites

1. Azure CLI installed (`az --version`)
2. Bicep CLI installed (`az bicep --version`)
3. Azure Subscription with Owner/Contributor role
4. Entra ID Groups created with Object IDs

### Entra ID Groups (Pre-create)

| Group Name | Purpose | SQL Permission | Redis | Members |
|-----------|---------|---------------|-------|---------|
| `DB-Ewa-Prod-Manager` | 管理員 | db_datareader + db_datawriter + db_ddladmin + EXECUTE + Type (Server Admin) | Cache User | IT Admin Users |
| `DB-Ewa-Prod-WebAppExecutor` | 後端機器連線 | db_datareader + db_datawriter + db_ddladmin + EXECUTE + Type | Cache User | App Service Enterprise Application |
| `DB-Ewa-Prod-Reader` | 唯讀查詢 | db_datareader | - | 報表/查詢人員 |

> **重要**: WebAppExecutor 群組加入的是 App Service 的 **Enterprise Application (Service Principal)**，不是使用者帳號。DB 只允許 backend/api 相關機器連線。

### Deployment Command

```bash
# 1. Clone & Prepare
cd EWA_init_maintenance

# 2. Set Entra ID Object IDs
export ENTRA_MANAGER_GROUP_OBJECT_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export ENTRA_READER_GROUP_OBJECT_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export ENTRA_WEBAPPEXECUTOR_GROUP_OBJECT_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# 3. Deploy
chmod +x scripts/deploy-infrastructure.sh
./scripts/deploy-infrastructure.sh
```

### Post-Deployment SQL Setup

執行 `scripts/setup-sql-users.sql`，使用 DB-Ewa-Prod-Manager 群組 Entra ID 身分登入 Query Editor 後執行。

```bash
# 透過 AZ CLI 執行 SQL 腳本 (使用 Entra ID 登入)
az account get-access-token --resource https://database.windows.net --query accessToken -o tsv | \
sqlcmd -S sql-ewa-prod.database.windows.net -d db-ewa-prod -G -i scripts/setup-sql-users.sql
```

### GitHub Actions Deployment

1. Setup Azure OIDC Federation (see `.github/workflows/deploy-infrastructure.yml`)
2. Add GitHub Secrets:
   - `AZURE_CLIENT_ID` - Service Principal Client ID
   - `AZURE_TENANT_ID` - Azure AD Tenant ID
   - `AZURE_SUBSCRIPTION_ID` - Subscription ID
   - `ENTRA_MANAGER_GROUP_OBJECT_ID` - Manager Group Object ID
   - `ENTRA_READER_GROUP_OBJECT_ID` - Reader Group Object ID
   - `ENTRA_WEBAPPEXECUTOR_GROUP_OBJECT_ID` - WebAppExecutor Group Object ID
3. Trigger: Manual `workflow_dispatch` or push to `bicep/**` on `main`

### App Service Clone (Multi-App Batch)

使用 `app-clone-batch.yml` 可批次 clone 多個 App Service，支援藍綠部署：

```json
// batch_spec JSON 範例
[
  {
    "source_subscription": "PI_azure",
    "source_rg": "RG_Ewa_Production",
    "source_name": "ewa-internal-api-earnedwageaccess",
    "targets": [
      {
        "target_name": "ewa-api-prod-clone",
        "target_rg": "RG_Ewa_Production_Clone"
      }
    ]
  }
]
```

#### Blue-Green Deployment (Slot)

啟用 `clone_to_slot=true` 後，會在目標 App Service 建立預覽 slot (`slot_name=preview`)：

```
┌──────────────────────────────────────────────────────┐
│                  App Service                          │
│  ┌──────────────────┐    ┌──────────────────────┐   │
│  │ Production Slot   │    │ Preview Slot         │   │
│  │ (Live Traffic)    │    │ (new-version)        │   │
│  │ Stable version    │    │ Cloned from source   │   │
│  └──────────────────┘    └──────────────────────┘   │
│           ▲                        │                  │
│           │     Swap (预热后)        │                  │
│           └────────────────────────┘                  │
└──────────────────────────────────────────────────────┘
```

**工作流程**：App Service Clone → Configure Settings/IP/VNet → Create Preview Slot → Clone Config to Slot → Swap Preview → Production

#### Slot Clone 流程

| Step | Action | Description |
|------|--------|-------------|
| 1 | Clone App Service | 建立目標 App Service |
| 2 | Configure Settings | 複製 App Settings / Connection Strings / IP 白名單 |
| 3 | Enable Managed Identity | 啟用 System-Assigned MI |
| 4 | Configure VNet | 設定 VNet Integration + Route All |
| 5 | Disable Basic Auth | 禁用 FTP/SCM Basic Auth |
| 6 | Create Preview Slot | 建立 `preview` slot，自動 clone production config |
| 7 | Clone Config to Slot | 複製 appsettings / connection strings 到 slot |
| 8 | Swap (optional) | `swap_after_clone=true` 將 slot 交換到 production |
| 9 | Restart | 重啟 App Service |

---

## Application Configuration

### Connection Strings (App Service Environment Variables)

| Variable | Value |
|----------|-------|
| `ASPNETCORE_ENVIRONMENT` | Production |
| `TZ` | Asia/Taipei |
| `WEBSITE_HTTPLOGGING_RETENTION_DAYS` | 60 |
| `REDIS_HOST_NAME` | redis-ewa-prod.redis.cache.windows.net |

### SQL Connection String (App Service → Configuration → Connection Strings)

```
Name:  DefaultConnection  
Type:  SQLAzure
Value: Server=tcp:sql-ewa-prod.database.windows.net,1433;Database=db-ewa-prod;Authentication=Active Directory Managed Identity;
```

---

## Security Features Summary

| Feature | Status |
|---------|--------|
| Entra ID Only Authentication (SQL) | ✓ Enabled |
| Access Key Disabled (Redis) | ✓ Enabled |
| Azure AD Only Authentication (SQL) | ✓ Enabled |
| Three-tier Group RBAC (Manager/WebAppExecutor/Reader) | ✓ Enforced |
| DB Backend-only Access (WebAppExecutor Group) | ✓ Enforced |
| HTTPS Only | ✓ Enabled |
| TLS 1.2 Minimum | ✓ Enabled |
| FTPS Only | ✓ Enabled |
| Basic Auth Publishing Disabled | ✓ Enabled |
| Client Affinity Disabled | ✓ Enabled |
| IP Restrictions (Default: Deny) | ✓ Enabled |
| WAF (Front Door) | ✓ Enabled |
| NTLM Disabled (Linux App Service) | ✓ (Linux default) |
| No SQL Password / No Redis Key | ✓ Architecture enforced |

---

## Estimated Costs

| Resource | SKU | Estimated Monthly |
|----------|-----|-------------------|
| App Service Plan | P0v3 (1 instance) | ~$140 |
| SQL Elastic Pool | Standard DTU 50 | ~$75 |
| SQL Database | 1 DB in Pool (100GB) | Included in Pool |
| Redis Enterprise | E10 (12 GB) | ~$250 |
| Front Door | Standard | ~$35 |
| NAT Gateway | Standard + Static IP | ~$35 |
| **Total** | | **~$535/mo** |

*Note: Actual costs vary by region and usage. Japan West pricing may differ. Pool DTU 可在 Portal 動態調整，無需停機。*

---

## File Structure

```
EWA_init_maintenance/
├── .github/workflows/
│   ├── deploy-infrastructure.yml       # 基礎架構部署 (Bicep)
│   ├── app-ops.yml                     # App Service 單一操作 (clone/delete/config)
│   └── app-clone-batch.yml             # 批次 App clone (支援 slot/藍綠)
├── bicep/
│   ├── main.bicep                      # 主模板 (Subscription Scope)
│   ├── vnet.bicep                      # VNet + NAT Gateway
│   ├── sql.bicep                       # SQL Server + Elastic Pool + Firewall
│   ├── redis.bicep                     # Redis Enterprise + Entra ID
│   ├── appservice.bicep                # App Service + VNet + IP
│   └── frontdoor.bicep                 # Front Door
├── scripts/
│   ├── deploy-infrastructure.sh        # 一鍵部署腳本
│   ├── setup-sql-users.sql             # SQL Entra ID Group User 建立
│   ├── SqlEntraIdHelper.cs             # SQL Entra ID 連線範例
│   └── RedisEntraIdHelper.cs           # Redis Entra ID 連線範例
├── deploy-appservice-ewa-production.sh # EWA Production App 部署腳本
├── purge-frontdoorCache2.sh            # Front Door Cache 清除
├── setup-frontdoor-domain_ewa-test.sh  # Front Door Custom Domain 設定
└── ARCHITECTURE.md                     # 本文件
```
