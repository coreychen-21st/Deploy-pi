// =============================================================================
// Azure SQL 連線範例 - 使用 Entra ID Managed Identity (無密碼)
// 適用於 App Service 環境
// =============================================================================

using Microsoft.Data.SqlClient;
using Azure.Identity;
using Azure.Core;

// =============================================================================
// 方案 1: 使用 Connection String + DefaultAzureCredential (推薦)
// Connection String 格式:
// Server=tcp:sql-ewa-prod.database.windows.net,1433;Database=db-ewa-prod;Authentication=Active Directory Managed Identity;
// =============================================================================

// App Settings 中的 Connection String
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection");

using var connection = new SqlConnection(connectionString);
// DefaultAzureCredential 會自動嘗試 Managed Identity → Environment Credential → Azure CLI
await connection.OpenAsync();

// =============================================================================
// 方案 2: 使用 DefaultAzureCredential 獲取 Token (手動注入)
// =============================================================================
public static class SqlEntraIdExtensions
{
    public static IServiceCollection AddSqlWithEntraId(
        this IServiceCollection services, 
        IConfiguration configuration)
    {
        services.AddScoped<SqlConnection>(sp =>
        {
            var config = sp.GetRequiredService<IConfiguration>();
            var connectionString = config.GetConnectionString("DefaultConnection");

            var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
            {
                // App Service 環境會自動使用 Managed Identity
                ManagedIdentityClientId = null // 使用 System-Assigned Managed Identity
            });

            var token = credential.GetToken(
                new TokenRequestContext(
                    new[] { "https://database.windows.net/.default" }
                ));

            var connection = new SqlConnection(connectionString);
            connection.AccessToken = token.Token;

            return connection;
        });

        return services;
    }
}

// =============================================================================
// 方案 3: 使用 Workload Identity (AKS / GitHub Actions)
// =============================================================================
public static async Task<SqlConnection> CreateWorkloadIdentityConnection()
{
    var credential = new WorkloadIdentityCredential();

    var token = await credential.GetTokenAsync(
        new TokenRequestContext(new[] { "https://database.windows.net/.default" })
    );

    var connection = new SqlConnection(
        "Server=tcp:sql-ewa-prod.database.windows.net,1433;" +
        "Database=db-ewa-prod;"
    );
    connection.AccessToken = token.Token;

    return connection;
}

// =============================================================================
// 方案 4: Program.cs DI 註冊 (ASP.NET Core)
// =============================================================================
// var builder = WebApplication.CreateBuilder(args);
//
// builder.Services.AddSqlWithEntraId(builder.Configuration);
//
// // 或者使用 Connection String
// builder.Services.AddDbContext<AppDbContext>((sp, options) =>
// {
//     var config = sp.GetRequiredService<IConfiguration>();
//     var connString = config.GetConnectionString("DefaultConnection");
//     options.UseSqlServer(connString);
// });

// =============================================================================
// 方案 5: 直接使用 ManagedIdentityCredential
// =============================================================================
public static async Task<SqlConnection> CreateManagedIdentityConnection(
    string server,
    string database,
    string? userAssignedClientId = null)
{
    var credential = new ManagedIdentityCredential(userAssignedClientId);

    var token = await credential.GetTokenAsync(
        new TokenRequestContext(new[] { "https://database.windows.net/.default" })
    );

    var connection = new SqlConnection(
        $"Server=tcp:{server},1433;Database={database};"
    );
    connection.AccessToken = token.Token;

    return connection;
}
