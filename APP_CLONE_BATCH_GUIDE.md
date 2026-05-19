# App Clone Batch 快速操作指南

## 基本概念

`app-clone-batch.yml` 會呼叫 `app-ops.yml` 來批量複製 Azure App Service，
支援跨 subscription / resource group 的 clone、slot（blue-green）、VNet、IP 白名單等完整設定。

## 快速使用

### 1. 準備 batch_spec JSON

建立一個 JSON 檔案（參考 `batch_spec_sample.json`）：

```json
[
  {
    "source_subscription": "PI_azure",
    "source_rg": "clone-test",
    "source_name": "test-ewa",
    "targets": [
      {
        "target_name": "clone-ewa",
        "target_rg": "clone-test",
        "app_service_plan": "clone-ewa-linux"
      }
    ]
  },
  {
    "source_subscription": "PI_azure",
    "source_rg": "clone-test",
    "source_name": "test-api-earnedwageaccess",
    "targets": [
      {
        "target_name": "clone-api-ewa",
        "target_rg": "clone-test",
        "app_service_plan": "clone-api-ewa"
      }
    ]
  }
]
```

#### 欄位說明

| 欄位 | 必填 | 說明 |
|------|------|------|
| `source_subscription` | ✅ | 來源訂閱 ID 或名稱（見下方訂閱名映射表） |
| `source_rg` | ✅ | 來源 resource group |
| `source_name` | ✅ | 來源 App Service 名稱 |
| `targets[].target_name` | ✅ | 目標 App Service 名稱 |
| `targets[].target_rg` | ❌ | 目標 RG（預設同 source_rg） |
| `targets[].target_subscription` | ❌ | 目標訂閱（預設同 source） |
| `targets[].app_service_plan` | ❌ | App Service Plan 名稱（預設 `asp-<target_name>`） |
| `targets[].docker_image` | ❌ | Docker image 覆寫（空 = 使用來源設定） |
| `targets[].app_runtime` | ❌ | Runtime stack（預設 `DOTNETCORE:8.0`） |
| `targets[].vnet_subnet_id` | ❌ | VNet subnet resource ID |
| `targets[].vnet_id` | ❌ | VNet resource ID |
| `targets[].subnet_name` | ❌ | Subnet name |

#### 訂閱名稱映射表

| 簡寫名稱 | 完整 Subscription ID |
|----------|---------------------|
| `CA804030` | `c9f80f0b-7d34-4410-a79c-ca23fb550d20` |
| `CA808046` | `fc6b18ca-199c-4123-8097-834cfc7ac213` |
| `DataTeam` | `26d35140-67ac-4d20-be0d-fe442ce0a926` |
| `PI_azure` | `99804447-bee3-4371-9bd5-672a86845c40` |

> 也可以直接填完整的 subscription UUID。

---

### 2. 執行 Workflow

1. GitHub Repo → **Actions** → **App Clone Batch**
2. 點擊 **Run workflow**
3. 填寫參數：

| 參數 | 建議值 | 說明 |
|------|--------|------|
| `environment` | `dev` | 環境標記 |
| `location` | `Southeast Asia` | 新建 RG 時的 fallback location |
| `dry_run` | ✅ true | 先 dry run 看結果，確認無誤再關掉 |
| `action` | `clone` | clone 或 delete |
| `batch_spec` | 貼入上述 JSON | 必須是合法 JSON |
| `max_parallel` | `2` | 同時跑幾個 clone job |
| `clone_to_slot` | ❌ false | 是否建立 preview slot |
| `swap_after_clone` | ❌ false | 是否 swap 到 production |
| `skip_identity` | ❌ false | 跳過 Managed Identity |
| `skip_vnet` | ❌ false | 跳過 VNet Integration |
| `clone_appsettings` | ✅ true | 複製來源 app settings |
| `clone_connectionstrings` | ✅ true | 複製 connection strings |
| `clone_iprestrictions` | ✅ true | 複製 IP 白名單 |

4. 點擊 **Run workflow**

---

### 3. Dry Run 範例輸出

```
==============================================
 DRY RUN - Configuration Preview
==============================================
Action:          clone
Source:          clone-test/test-ewa
Target:          PI_azure/clone-test/clone-ewa
Location:        southeastasia
App Service Plan: clone-ewa-linux
Runtime/Docker:  DOTNETCORE:8.0 /

Features:
  Clone AppSettings:      true
  Clone ConnectionStrings:true
  Clone IP Restrictions:  true
  Skip Managed Identity:  false
  Skip VNet Integration:  false

Slot:            
Swap to Prod:    false
```

---

## 常見範例

### 範例 1：基本 clone（同 RG）

```json
[
  {
    "source_subscription": "PI_azure",
    "source_rg": "prod-rg",
    "source_name": "app-prod",
    "targets": [{ "target_name": "app-stage", "target_rg": "stage-rg" }]
  }
]
```

### 範例 2：跨 subscription clone

```json
[
  {
    "source_subscription": "CA804030",
    "source_rg": "ewa-prod",
    "source_name": "ewa-api",
    "targets": [
      {
        "target_subscription": "PI_azure",
        "target_rg": "ewa-dev",
        "target_name": "ewa-api-dev"
      }
    ]
  }
]
```

### 範例 3：使用 Docker image

```json
[
  {
    "source_subscription": "PI_azure",
    "source_rg": "ewa-prod",
    "source_name": "ewa-web",
    "targets": [
      {
        "target_rg": "ewa-test",
        "target_name": "ewa-web-test",
        "docker_image": "coreychen.azurecr.io/ewa-web:latest",
        "app_service_plan": "ewa-test-plan"
      }
    ]
  }
]
```

### 範例 4：Blue-Green deployment（Slot + Swap）

```json
[
  {
    "source_subscription": "PI_azure",
    "source_rg": "ewa-prod",
    "source_name": "ewa-app",
    "targets": [{ "target_name": "ewa-app-new" }]
  }
]
```

執行時勾選：
- `clone_to_slot`: ✅ true
- `slot_name`: `preview`
- `swap_after_clone`: ✅ true

### 範例 5：批量刪除

```json
[
  {
    "source_subscription": "PI_azure",
    "source_rg": "ewa-dev",
    "source_name": "old-app-1",
    "targets": [{ "target_name": "old-app-1", "target_rg": "ewa-dev" }]
  },
  {
    "source_subscription": "PI_azure",
    "source_rg": "ewa-dev",
    "source_name": "old-app-2",
    "targets": [{ "target_name": "old-app-2", "target_rg": "ewa-dev" }]
  }
]
```

> ⚠️ 刪除時需勾選 `confirm` = true，且建議先 dry_run = true 確認

---

## 支援的 Location 選項

| 選項名稱 | 實際 Azure 區域 |
|----------|----------------|
| Japan East | `japaneast` |
| Japan West | `japanwest` |
| East asia | `eastasia` |
| Southeast Asia | `southeastasia` |
| taiwannorth | `taiwannorth` |
| CUSTOM | 需另填 `location_custom` |

> ⚠️ `southasia` 不在列表內，請使用 `Southeast Asia` 或 `CUSTOM` 填 `southindia` / `southafricanorth`
