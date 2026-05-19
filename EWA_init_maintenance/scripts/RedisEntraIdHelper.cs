// =============================================================================
// Azure Managed Redis 連線範例 - 使用 Entra ID Token Authentication (無密碼/無 Key)
// 適用於 App Service 環境
// =============================================================================

using StackExchange.Redis;
using Azure.Identity;
using Azure.Core;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Configuration;

// =============================================================================
// 方案 1: 使用 DefaultAzureCredential + Token Refresh (推薦)
// Connection String 格式:
// redis-ewa-prod.redis.cache.windows.net:10000,ssl=True,abortConnect=False
// =============================================================================

public static class RedisEntraIdExtensions
{
    /// <summary>
    /// 註冊 Redis ConnectionMultiplexer (Singleton, Token 自動刷新)
    /// </summary>
    public static IServiceCollection AddRedisWithEntraId(
        this IServiceCollection services,
        IConfiguration configuration,
        string hostName)
    {
        services.AddSingleton<IConnectionMultiplexer>(sp =>
        {
            var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
            {
                ManagedIdentityClientId = null // 使用 System-Assigned Managed Identity
            });

            var tokenRefreshInterval = TimeSpan.FromHours(1);
            var tokenProvider = new DefaultAzureCredentialTokenProvider(
                credential,
                hostName,
                tokenRefreshInterval
            );

            return ConnectionMultiplexer.Connect(
                new ConfigurationOptions
                {
                    EndPoints = { { hostName, 10000 } },
                    Ssl = true,
                    AbortOnConnectFail = false,
                    ConnectTimeout = 15000,
                    SyncTimeout = 15000,
                    Password = tokenProvider.GetToken(),      // 當作 Password 傳入
                    User = "managed-identity"                 // Username 任意值
                },
                Console.Out
            );
        });

        services.AddScoped<IDatabase>(sp =>
        {
            var multiplexer = sp.GetRequiredService<IConnectionMultiplexer>();
            return multiplexer.GetDatabase();
        });

        return services;
    }

    /// <summary>
    /// Token Provider with automatic refresh
    /// </summary>
    private class DefaultAzureCredentialTokenProvider : IDisposable
    {
        private readonly TokenCredential _credential;
        private readonly string _hostName;
        private readonly TimeSpan _refreshInterval;
        private readonly Timer _timer;
        private string _currentToken;

        public DefaultAzureCredentialTokenProvider(
            TokenCredential credential,
            string hostName,
            TimeSpan refreshInterval)
        {
            _credential = credential;
            _hostName = hostName;
            _refreshInterval = refreshInterval;
            _currentToken = GetToken();

            _timer = new Timer(
                _ =>
                {
                    try
                    {
                        _currentToken = GetToken();
                        Console.WriteLine("[RedisEntraId] Token refreshed successfully");
                    }
                    catch (Exception ex)
                    {
                        Console.Error.WriteLine($"[RedisEntraId] Token refresh failed: {ex.Message}");
                    }
                },
                null,
                refreshInterval,
                refreshInterval
            );
        }

        public string GetToken()
        {
            var token = _credential.GetToken(
                new TokenRequestContext(
                    new[] { "acca5fbb-b7e4-4009-81f1-37e38fd66d78/.default" }
                )
            );
            return token.Token;
        }

        public void Dispose()
        {
            _timer?.Dispose();
        }
    }
}

// =============================================================================
// 方案 2: 自訂 ConnectionMultiplexer Factory (支援 Token Refresh)
// =============================================================================
public class EntraIdRedisConnectionFactory : IDisposable
{
    private readonly SemaphoreSlim _lock = new(1, 1);
    private IConnectionMultiplexer? _connection;
    private readonly TokenCredential _credential;
    private readonly string _hostName;
    private string? _currentToken;
    private DateTime _tokenExpiry;

    public EntraIdRedisConnectionFactory(string hostName)
    {
        _hostName = hostName;
        _credential = new DefaultAzureCredential();
    }

    public async Task<IConnectionMultiplexer> GetConnectionAsync()
    {
        await _lock.WaitAsync();
        try
        {
            if (_connection == null || !_connection.IsConnected || TokenNeedsRefresh())
            {
                _connection?.Dispose();
                _currentToken = await GetTokenAsync();
                _connection = await ConnectionMultiplexer.ConnectAsync(
                    new ConfigurationOptions
                    {
                        EndPoints = { { _hostName, 10000 } },
                        Ssl = true,
                        AbortOnConnectFail = false,
                        Password = _currentToken,
                        User = "managed-identity",
                        AllowAdmin = false
                    }
                );
            }
            return _connection;
        }
        finally
        {
            _lock.Release();
        }
    }

    private async Task<string> GetTokenAsync()
    {
        var token = await _credential.GetTokenAsync(
            new TokenRequestContext(
                new[] { "acca5fbb-b7e4-4009-81f1-37e38fd66d78/.default" }
            ),
            CancellationToken.None
        );
        _tokenExpiry = token.ExpiresOn.UtcDateTime;
        return token.Token;
    }

    private bool TokenNeedsRefresh()
    {
        return _currentToken == null || DateTime.UtcNow.AddMinutes(5) >= _tokenExpiry;
    }

    public void Dispose()
    {
        _connection?.Dispose();
        _lock.Dispose();
    }
}

// =============================================================================
// 方案 3: Program.cs 註冊 (ASP.NET Core)
// =============================================================================
// var builder = WebApplication.CreateBuilder(args);
//
// var redisHostName = Environment.GetEnvironmentVariable("REDIS_HOST_NAME")
//     ?? builder.Configuration["Redis:HostName"];
//
// builder.Services.AddRedisWithEntraId(builder.Configuration, redisHostName!);
//
// // 使用範例
// public class WeatherService(IDatabase cache)
// {
//     public async Task<string?> GetCachedValueAsync(string key)
//         => await cache.StringGetAsync(key);
//
//     public async Task SetCachedValueAsync(string key, string value, TimeSpan? expiry = null)
//         => await cache.StringSetAsync(key, value, expiry);
// }

// =============================================================================
// 方案 4: 單次連線 (非 Singleton, 每次建立)
// =============================================================================
public static class RedisEntraIdQuickConnect
{
    public static async Task<ConnectionMultiplexer> ConnectAsync(
        string hostName,
        int port = 10000)
    {
        var credential = new DefaultAzureCredential();

        var token = await credential.GetTokenAsync(
            new TokenRequestContext(
                new[] { "acca5fbb-b7e4-4009-81f1-37e38fd66d78/.default" }
            )
        );

        return await ConnectionMultiplexer.ConnectAsync(
            new ConfigurationOptions
            {
                EndPoints = { { hostName, port } },
                Ssl = true,
                AbortOnConnectFail = false,
                Password = token.Token,
                User = "managed-identity",
                AllowAdmin = false
            }
        );
    }
}

// =============================================================================
// Environment Variables 設定 (於 App Service Configuration)
// =============================================================================
// REDIS_HOST_NAME = redis-ewa-prod.redis.cache.windows.net
