-- =============================================================================
-- Azure SQL Database Users Setup - Entra ID Group Based
-- DB-Ewa-Prod-Manager / DB-Ewa-Prod-WebAppExecutor / DB-Ewa-Prod-Reader
-- 使用 DB-Ewa-Prod-Manager 群組 Entra ID 身分登入後執行
-- =============================================================================

-- Manager: RW + DDL + EXECUTE + Type Permissions (兼 Server Admin)
CREATE USER [DB-Ewa-Prod-Manager] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [DB-Ewa-Prod-Manager];
ALTER ROLE db_datawriter ADD MEMBER [DB-Ewa-Prod-Manager];
ALTER ROLE db_ddladmin ADD MEMBER [DB-Ewa-Prod-Manager];
GRANT EXECUTE TO [DB-Ewa-Prod-Manager];
GRANT EXECUTE ON TYPE::[dbo].[StringContainerType] TO [DB-Ewa-Prod-Manager];
GRANT REFERENCES ON TYPE::[dbo].[StringContainerType] TO [DB-Ewa-Prod-Manager];
GRANT EXECUTE ON TYPE::[dbo].[IntContainerType] TO [DB-Ewa-Prod-Manager];
GRANT REFERENCES ON TYPE::[dbo].[IntContainerType] TO [DB-Ewa-Prod-Manager];

-- WebAppExecutor: RW + DDL + EXECUTE + Type (給 App Service Managed Identity)
CREATE USER [DB-Ewa-Prod-WebAppExecutor] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [DB-Ewa-Prod-WebAppExecutor];
ALTER ROLE db_datawriter ADD MEMBER [DB-Ewa-Prod-WebAppExecutor];
ALTER ROLE db_ddladmin ADD MEMBER [DB-Ewa-Prod-WebAppExecutor];
GRANT EXECUTE TO [DB-Ewa-Prod-WebAppExecutor];
GRANT EXECUTE ON TYPE::[dbo].[StringContainerType] TO [DB-Ewa-Prod-WebAppExecutor];
GRANT REFERENCES ON TYPE::[dbo].[StringContainerType] TO [DB-Ewa-Prod-WebAppExecutor];
GRANT EXECUTE ON TYPE::[dbo].[IntContainerType] TO [DB-Ewa-Prod-WebAppExecutor];
GRANT REFERENCES ON TYPE::[dbo].[IntContainerType] TO [DB-Ewa-Prod-WebAppExecutor];

-- Reader: Read Only
CREATE USER [DB-Ewa-Prod-Reader] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [DB-Ewa-Prod-Reader];
