# API (.NET 10)

An ASP.NET Core minimal API. It runs as a container image on AWS Lambda behind API Gateway HTTP API, stores data in MongoDB,
and accepts Cognito access tokens. Locally, an Aspire AppHost runs it next to a MongoDB container.

## Contents
- [Layout](#layout)
- [Packages](#packages)
- [Project files](#project-files)
- [Program.cs](#programcs)
- [Domain: models and repositories](#domain-models-and-repositories)
- [Infrastructure: MongoDB and Cognito](#infrastructure-mongodb-and-cognito)
- [The user feature](#the-user-feature)
- [OpenAPI transformer](#openapi-transformer)
- [Container and local dev](#container-and-local-dev)
- [Tests and done criteria](#tests-and-done-criteria)

## Layout

```
api/
  <Company>.<App>.slnx
  <Company>.<App>.Api/              # endpoints, DTOs, mapping, Program.cs, Dockerfile
    Endpoints/  Models/  Extensions/  Providers/  Transformers/  Properties/launchSettings.json
  <Company>.<App>.Domain/           # entities, services, repository interfaces; references nothing
    Models/Common/  Repositories/Common/  Services/Interfaces/  Providers/  Exceptions/
  <Company>.<App>.Infrastructure/   # MongoDB, AWS and vendor adapters; references Domain
    Configurations/  Enumerations/  Extensions/  MongoDB/  Services/
  <Company>.<App>.AppHost/          # Aspire, local dev only
  <Company>.<App>.Api.Tests/
  <Company>.<App>.Domain.Tests/
openapi/api.json                    # written by the Api build; the clients are generated from it
```

Conventions:
- One static class per resource in `Endpoints/<Resource>Endpoint.cs`, using a C# 14 extension block (`extension(WebApplication app) { internal void Map<Resource>Endpoints() { ... } }`), called from `Program.cs`.
- Request and response DTOs (`<Thing>Request`, `<Thing>Response`) live in `Api/Models`. Mapping from entities is done by extension methods in `Api/Extensions/<Thing>Extension.cs` (`ToResponse<Thing>()`). Endpoints never return entities.
- Business rules live in Domain services (`I<Thing>Service` in `Services/Interfaces`), not in endpoints. Endpoints translate exceptions to results: `ArgumentException` becomes `TypedResults.BadRequest(ex.Message)`.
- Infrastructure is registered through `Infrastructure/Extensions/<Thing>ServiceExtension.cs` (`AddXxxService(configuration)`), and each one reads a typed config section through `ConfigurationExtension.GetXxxConfig()`. Domain services and repositories are registered in `Program.cs`.
- Config sections are PascalCase (`Auth`, `Database`). In Lambda they're set as env vars with `__` (`Auth__Authority`). Locally they come from user secrets.
- `Nullable` and `ImplicitUsings` are enabled everywhere, with target `net10.0`.

## Packages

| Project | Package | Version |
| --- | --- | --- |
| Api | Amazon.Lambda.AspNetCoreServer.Hosting | 2.2.1 |
| Api | Microsoft.AspNetCore.Authentication.JwtBearer | 10.0.14 |
| Api | Microsoft.AspNetCore.OpenApi | 10.0.14 |
| Api | Microsoft.Extensions.ApiDescription.Server (PrivateAssets all) | 10.0.14 |
| Api | Scalar.AspNetCore | 2.19.0 |
| Infrastructure | AWSSDK.Extensions.NETCore.Setup | 4.0.102.8 |
| Infrastructure | AWSSDK.CognitoIdentityProvider | 4.0.106.7 |
| Infrastructure | MongoDB.Driver | 3.13.0 |
| Infrastructure | Microsoft.Extensions.Configuration.Binder | 10.0.14 |
| AppHost | SDK `Aspire.AppHost.Sdk/13.6.4`, Aspire.Hosting.MongoDB | 13.6.4 |
| Tests | Microsoft.NET.Test.Sdk 17.14.1, xunit 2.9.3, xunit.runner.visualstudio 3.1.4, NSubstitute 6.2.0, coverlet.collector 6.0.4 | |

The required modules add `AWSSDK.SimpleEmailV2 4.0.106.8` and `AWSSDK.S3 4.0.104.9` to Infrastructure. Optional modules add their own packages (see `modules.md`).

## Project files

Api csproj. `OpenApiDocumentsDirectory` makes every build write `openapi/api.json`:

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <UserSecretsId><new GUID></UserSecretsId>
    <PublishReadyToRun>true</PublishReadyToRun>
    <OpenApiDocumentsDirectory>../../openapi</OpenApiDocumentsDirectory>
    <OpenApiGenerateDocumentsOptions>--file-name api --openapi-version OpenApi3_0</OpenApiGenerateDocumentsOptions>
  </PropertyGroup>
  <!-- PackageReferences from the table; ProjectReferences to Domain and Infrastructure -->
  <ItemGroup>
    <InternalsVisibleTo Include="<Company>.<App>.Api.Tests" />
  </ItemGroup>
</Project>
```

Generate a fresh GUID for each `UserSecretsId`. The `.slnx` lists every project as `<Project Path="..." />` inside `<Solution>`.

## Program.cs

Copy this structure exactly. Modules add registrations where the comments show.

```csharp
using Amazon.SimpleEmailV2;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using <Company>.<App>.Api.Endpoints;
using <Company>.<App>.Api.Providers;
using <Company>.<App>.Api.Transformers;
using <Company>.<App>.Domain.Providers;
using <Company>.<App>.Domain.Repositories;
using <Company>.<App>.Domain.Repositories.Common;
using <Company>.<App>.Domain.Services;
using <Company>.<App>.Domain.Services.Interfaces;
using <Company>.<App>.Infrastructure.Extensions;
using <Company>.<App>.Infrastructure.MongoDB;
using Scalar.AspNetCore;
using System.Text.Json.Serialization;

const string CorsPolicyName = "<App>";

var builder = WebApplication.CreateSlimBuilder(args);
builder.WebHost.UseKestrelHttpsConfiguration(); // the slim builder leaves out HTTPS; the "https" launch profile needs it

builder.Services.AddOpenApi(options =>
{
    options.OpenApiVersion = Microsoft.OpenApi.OpenApiSpecVersion.OpenApi3_0;
    options.AddDocumentTransformer<NullableEnumSchemaTransformer>();
});

// Only used in Development; in AWS, API Gateway answers CORS.
builder.Services.AddCors(options =>
{
    options.AddPolicy(CorsPolicyName, policy =>
    {
        var origins = builder.Configuration.GetSection("Cors:Origins")?.Get<string[]>() ?? [];
        policy.WithOrigins(origins).AllowAnyHeader().AllowAnyMethod().AllowCredentials();
    });
});

builder.Services.AddAWSLambdaHosting(LambdaEventSource.HttpApi);

builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.NumberHandling = JsonNumberHandling.Strict;
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter());
});

builder.Services.AddDatabaseService(builder.Configuration);
builder.Services.AddIdentityProviderUserService();
// Required modules (modules.md): images and email.
builder.Services.AddImageService(builder.Configuration);
builder.Services.AddAWSService<IAmazonSimpleEmailServiceV2>();
builder.Services.AddEmailNotificationService(builder.Configuration);
// Optional modules: builder.Services.AddXxxService(builder.Configuration);

var authConfig = builder.Configuration.GetAuthConfig();

builder.Services.AddAuthentication().AddJwtBearer(JwtBearerDefaults.AuthenticationScheme, options =>
{
    options.Authority = authConfig.Authority;
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateLifetime = true,
        // Cognito access tokens have no "aud"; the app client is in "client_id". Accept the web, Android and iOS clients.
        AudienceValidator = (audiences, securityToken, validationParameters) =>
        {
            var jwt = securityToken as JsonWebToken;
            var clientId = jwt?.GetPayloadValue<string>("client_id")?.ToLower();
            return authConfig.ClientIds.Contains(clientId);
        }
    };
});

if (authConfig.SecureAllEndpoints)
{
    builder.Services.AddAuthorizationBuilder()
        .SetFallbackPolicy(new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build());
}
else
{
    builder.Services.AddAuthorizationBuilder();
}

builder.Services.AddAuthorization();
builder.Services.AddHttpContextAccessor();

builder.Services.AddScoped<IUserClaimProvider, UserClaimProvider>();

builder.Services.AddScoped(typeof(IRepository<>), typeof(MongoDBRepository<>));
builder.Services.AddScoped<IUserRepository, UserRepository>();

builder.Services.AddScoped<IUserService, UserService>();
builder.Services.AddScoped<IAccountDeletionService, AccountDeletionService>();

var app = builder.Build();

// The OpenAPI build step (dotnet-getdocument) runs this Main from its own process to produce openapi/api.json.
// Skip startup side effects there, such as connecting to MongoDB, which isn't reachable at build time.
if (System.Reflection.Assembly.GetEntryAssembly()?.GetName().Name == "<Company>.<App>.Api")
{
    app.Services.EnsureDatabaseIndexes();
}

if (app.Environment.IsDevelopment())
{
    app.UseCors(CorsPolicyName);
    app.MapOpenApi();
    app.MapScalarApiReference();
}

app.UseAuthentication();
app.UseAuthorization();

app.MapUserEndpoints();
app.MapImageEndpoints();
// Optional modules: app.MapXxxEndpoints();

app.Run();
```

`AuthConfig` (in `Infrastructure/Configurations`, section `Auth`) has `string Authority`, `IEnumerable<string> ClientIds` and
`bool SecureAllEndpoints = false`. `Authority` is `https://cognito-idp.<region>.amazonaws.com/<userPoolId>`.
Development user secrets set `Auth:Authority`, `Auth:ClientIds:0..2` (in lowercase), `Auth:SecureAllEndpoints=true`,
`Cors:Origins:0=http://localhost:5173` and `Database:ConnectionString`.

## Domain: models and repositories

```csharp
namespace <Company>.<App>.Domain.Models.Common
{
    public interface IAggregateRoot { }

    public abstract class BaseModel : IAggregateRoot
    {
        public virtual string? Id { get; set; }
        public Guid PublicId { get; set; } = Guid.NewGuid();   // the only id clients ever see
        public DateTime? CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public DateTime? LastAccessedAt { get; set; }
        public bool Deleted { get; set; }                      // soft delete; account deletion is the exception
    }
}
```

The repository interfaces live in `Repositories/Common` and are split by read and write, then combined:
- `IReadRepository<T>`: `RetrieveAllAsync`, `RetrieveAllActiveAsync`, `RetrieveByIdAsync(string)`, `RetrieveByPublicIdAsync(Guid)`, `IsExistAsync(string)`
- `IWriteRepository<T>`: `CreateAsync`, `UpdateAsync`, `DeleteAsync` (soft delete), `DeletePermanentlyAsync`, `string GenerateId()`
- `IRepository<T> : IReadRepository<T>, IWriteRepository<T> where T : class, IAggregateRoot`

Every method takes `CancellationToken cancellationToken = default`. An entity-specific repository extends the generic one
(`IUserRepository : IRepository<User>`) and adds only queries it needs.

## Infrastructure: MongoDB and Cognito

`MongoDBRepository<T>(IMongoDatabase db) : IRepository<T> where T : BaseModel` uses the collection named `typeof(T).Name`.
`GenerateId()` returns `ObjectId.GenerateNewId().ToString()`. `IsExistAsync` checks `CountDocumentsAsync(...) > 0`. `DeleteAsync` sets `Deleted = true`. `UpdateAsync` is
`ReplaceOneAsync` by `Id`, and `UpdateAsync` and `RetrieveAllActiveAsync` are `virtual`. Entity repositories subclass it
(`UserRepository : MongoDBRepository<User>, IUserRepository`) and use the protected `collection`.

`DbConfig` (section `Database`) has `Engine = DatabaseEngine.MongoDB`, `ConnectionString = "mongodb://username:password@localhost:27017/"`
(this must not be empty, because that breaks the OpenAPI build step) and `DatabaseName = "<App>"`.

```csharp
public static class DatabaseServiceExtension
{
    public static IServiceCollection AddDatabaseService(this IServiceCollection services, IConfiguration configuration)
    {
        var dbConfig = configuration.GetDbConfig();
        return dbConfig.Engine switch
        {
            DatabaseEngine.MongoDB => services.AddMongoDB(dbConfig.ConnectionString, dbConfig.DatabaseName),
            _ => throw new InvalidOperationException($"{nameof(AddDatabaseService)} error. Invalid engine: {dbConfig.Engine}.")
        };
    }

    private static IServiceCollection AddMongoDB(this IServiceCollection services, string connectionString, string databaseName)
    {
        BsonSerializer.RegisterSerializer(new GuidSerializer(GuidRepresentation.Standard));

        var pack = new ConventionPack { new EnumRepresentationConvention(BsonType.String) };
        ConventionRegistry.Register("EnumString", pack, t => true);

        // Old documents keep fields that were later removed from a model; don't fail on them.
        var conventions = new ConventionPack { new IgnoreExtraElementsConvention(true) };
        ConventionRegistry.Register("IgnoreExtraElements", conventions, type => true);

        var mongoClient = new MongoClient(connectionString);
        services.AddSingleton<IMongoClient>(mongoClient);
        services.AddSingleton(mongoClient.GetDatabase(databaseName));
        return services;
    }

    // Called explicitly after the host is built, not during registration, which also runs at build time for the
    // OpenAPI document, where no MongoDB is reachable.
    public static void EnsureDatabaseIndexes(this IServiceProvider serviceProvider)
    {
        var mongoDatabase = serviceProvider.GetRequiredService<IMongoDatabase>();

        EnsureUniquePublicIdIndex<User>(mongoDatabase);
        var users = mongoDatabase.GetCollection<User>(nameof(User));
        users.Indexes.CreateOne(new CreateIndexModel<User>(
            Builders<User>.IndexKeys.Ascending(d => d.ExternalUserId), new CreateIndexOptions { Unique = true }));
    }

    private static void EnsureUniquePublicIdIndex<T>(IMongoDatabase mongoDatabase) where T : BaseModel
    {
        var collection = mongoDatabase.GetCollection<T>(typeof(T).Name);
        collection.Indexes.CreateOne(new CreateIndexModel<T>(
            Builders<T>.IndexKeys.Ascending(d => d.PublicId), new CreateIndexOptions { Unique = true }));
    }
}
```

Every new entity gets `EnsureUniquePublicIdIndex<T>` and an index for each query it serves. Each index gets a comment
saying which query it serves.

Cognito adapter: the Domain interface `IIdentityProviderUserService` has `Task<string?> GetEmailAsync(string accessToken)` and
`Task DeleteUserAsync(string accessToken)`. The comment on `DeleteUserAsync` says it succeeds when the user is already gone,
so a retried account deletion can finish:

```csharp
public class CognitoIdentityProviderUserService(IAmazonCognitoIdentityProvider cognito) : IIdentityProviderUserService
{
    public async Task<string?> GetEmailAsync(string accessToken)
    {
        var response = await cognito.GetUserAsync(new GetUserRequest { AccessToken = accessToken });
        return response.UserAttributes.Find(attribute => attribute.Name == "email")?.Value;
    }

    public async Task DeleteUserAsync(string accessToken)
    {
        try
        {
            await cognito.DeleteUserAsync(new DeleteUserRequest { AccessToken = accessToken });
        }
        catch (UserNotFoundException)
        {
        }
    }
}
```

`AddIdentityProviderUserService()` registers `services.AddAWSService<IAmazonCognitoIdentityProvider>()` and the scoped adapter.
Both calls need the access token to carry the `aws.cognito.signin.user.admin` scope, which is why every client requests it.

## The user feature

This feature runs through every layer and is the pattern for new features.

- `User : BaseModel` has `required string ExternalUserId` (the Cognito `sub`), `string? Email` and `string? Name`.
- `IUserRepository.GetByExternalUserIdAsync(string externalUserId)`.
- `IUserClaimProvider` (Domain/Providers), implemented in `Api/Providers/UserClaimProvider`:

```csharp
public class UserClaimProvider(IHttpContextAccessor httpContextAccessor) : IUserClaimProvider
{
    public string GetExternalUserId()
    {
        return httpContextAccessor.HttpContext?.User.FindFirst("sub")?.Value
            ?? httpContextAccessor.HttpContext?.User.FindFirst(ClaimTypes.NameIdentifier)?.Value
            ?? throw new ArgumentNullException("ExternalUserId not found.");
    }

    public string? GetAccessToken()
    {
        var header = httpContextAccessor.HttpContext?.Request.Headers.Authorization.ToString();
        if (string.IsNullOrEmpty(header) || !header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }
        return header["Bearer ".Length..];
    }
}
```

Endpoints (`UserEndpoint`):

| Route | Does | Returns |
| --- | --- | --- |
| `POST /users` | `UserService.LogUserAsync(sub, accessToken)`. Every client calls this right after sign-in | `UserResponse` |
| `PUT /users/me` | updates the name (`UserUpdateRequest { string? Name }`) | `UserResponse` |
| `DELETE /users/me` | `AccountDeletionService.DeleteAccountAsync(sub, accessToken)`. Returns 400 if there's no token | 204 |

`UserResponse` has `PublicId`, `Email`, `Name` and `PhotoUrl`. For the photo endpoints and the welcome email, see the required modules in `modules.md`.

`UserService.LogUserAsync`: if no user has this `ExternalUserId`, create one with `Id = GenerateId()` and `CreatedAt = UtcNow`.
Look up the email from Cognito only on this first sign-up, so returning users don't pay for a Cognito call on every login.
For an existing user, backfill `Email` if it's null and a token exists, then set `LastAccessedAt` and update.
`UpdateNameAsync` trims the name, rejects anything over 100 characters with `ArgumentOutOfRangeException`, and stores an empty name as null.

`AccountDeletionService.DeleteAccountAsync` deletes permanently, not with the soft delete used elsewhere. Each step is safe
to repeat, and the user record goes last, so if any step fails the user can sign in and try again. The order is:
1. Delete all of the user's data from every other repository and external service. In a new app that means the user's image files, then their image records (the Images module).
   Each optional module adds its own step. Payment data goes first, so a deleted account can never be charged again.
2. `identityProviderUserService.DeleteUserAsync(accessToken)`. This comes before the user record, so a failure leaves the account in place to retry.
3. `userRepository.DeletePermanentlyAsync(user.Id)`.

Every new feature that stores user data must add itself to step 1. Say so in CLAUDE.md.

## OpenAPI transformer

Without this transformer, Orval generates invalid TypeScript for nullable enum properties:

```csharp
using Microsoft.AspNetCore.OpenApi;
using Microsoft.OpenApi;

namespace <Company>.<App>.Api.Transformers
{
    /// <summary>
    /// Nullable enum properties are emitted as oneOf [{ enum: [null] }, { $ref }], which orval turns into
    /// invalid TypeScript. Rewrite them to the OpenAPI 3.0 idiom: allOf [{ $ref }] with nullable: true.
    /// </summary>
    internal sealed class NullableEnumSchemaTransformer : IOpenApiDocumentTransformer
    {
        public Task TransformAsync(OpenApiDocument document, OpenApiDocumentTransformerContext context, CancellationToken cancellationToken)
        {
            foreach (var schema in document.Components?.Schemas?.Values.OfType<OpenApiSchema>() ?? [])
            {
                if (schema.Properties is null)
                {
                    continue;
                }

                foreach (var (name, property) in schema.Properties.ToList())
                {
                    if (property.OneOf is not { Count: 2 } oneOf)
                    {
                        continue;
                    }

                    var reference = oneOf.OfType<OpenApiSchemaReference>().SingleOrDefault();
                    var isNullOnly = oneOf.Any(candidate => candidate.Type == JsonSchemaType.Null);

                    if (reference is not null && isNullOnly)
                    {
                        schema.Properties[name] = new OpenApiSchema
                        {
                            Type = JsonSchemaType.Null,
                            AllOf = [reference]
                        };
                    }
                }
            }

            return Task.CompletedTask;
        }
    }
}
```

## Container and local dev

`Api/Dockerfile`. CI publishes first and copies the output into the image:

```dockerfile
FROM public.ecr.aws/lambda/dotnet:10
ARG COPY_FROM="."
WORKDIR /var/task
COPY ${COPY_FROM} .

CMD ["<Company>.<App>.Api.dll"]
```

The AppHost csproj uses `Sdk="Aspire.AppHost.Sdk/13.6.4"` and sets `<AspireUseCliBundle>true</AspireUseCliBundle>`. Without it, every build
warns with ASPIRE010.

`launchSettings.json` has profiles `http` (`http://localhost:5142`) and `https` (`https://localhost:7048;http://localhost:5142`),
both with `ASPNETCORE_ENVIRONMENT=Development` and `launchBrowser: false`. The mobile debug builds point at port 5142.

AppHost:

```csharp
using System.Net.Sockets;

var builder = DistributedApplication.CreateBuilder(args);

// Fixed port so the connection string in the Api's user secrets stays valid; persistent so data survives restarts.
var mongo = builder.AddMongoDB("mongo")
    .WithEndpoint("tcp", endpoint =>
    {
        endpoint.Port = 27017;
        endpoint.TargetPort = 27017;
        endpoint.Protocol = ProtocolType.Tcp;
    })
    .WithDataVolume()
    .WithMongoExpress()
    .WithLifetime(ContainerLifetime.Persistent);

builder.AddProject<Projects.<Company>_<App>_Api>("api")
    .WithEnvironment("DOTNET_ENVIRONMENT", "Development")
    .WaitFor(mongo);

builder.Build().Run();
```

`api/.gitignore` covers `bin/`, `obj/`, `.vs/`, `*.user` and `TestResults/`.

## Tests and done criteria

- `Domain.Tests` uses xUnit and NSubstitute, with `<Using Include="Xunit" />`. Cover `UserService` (creates on first login, looks up the email
  only then, backfills a missing email, trims and limits the name) and `AccountDeletionService` (Cognito deletion before the user record,
  and it finishes when the user record doesn't exist).
- `Api.Tests` covers `UserClaimProvider` (sub claim, NameIdentifier fallback, a Bearer header with odd casing, a missing header) and the DTO mapping extensions.
- **Done when:** `dotnet build api/<Company>.<App>.slnx` succeeds with no warnings, `openapi/api.json` exists and contains `/users` and `/users/me`,
  and `dotnet test api/<Company>.<App>.slnx` passes.
