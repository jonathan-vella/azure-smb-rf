using Azure.Identity;
using Microsoft.Azure.Cosmos;

namespace ManagementConsole.Api.Services;

public sealed class CosmosFactory
{
    public CosmosClient Client { get; }
    public Database Database { get; }

    public CosmosFactory(IConfiguration cfg)
    {
        var endpoint = cfg["COSMOS_ENDPOINT"]
            ?? throw new InvalidOperationException("COSMOS_ENDPOINT not set");
        var dbName = cfg["COSMOS_DATABASE"] ?? "console";

        Client = new CosmosClient(endpoint, new DefaultAzureCredential(), new CosmosClientOptions
        {
            // Custom serializer: camelCase POCO properties (matches the
            // existing on-disk schema) but preserve dictionary keys
            // verbatim. The built-in CamelCase policy mangles keys like
            // OWNER → oWNER and silently breaks parameter lockdown.
            Serializer = new SystemTextJsonCosmosSerializer(),
        });
        Database = Client.GetDatabase(dbName);
    }

    public Container Customers => Database.GetContainer("customers");
    public Container Deployments => Database.GetContainer("deployments");
    public Container AuditLog => Database.GetContainer("auditLog");
    public Container Settings => Database.GetContainer("settings");
}
