using ManagementConsole.Api.Models;
using Microsoft.Azure.Cosmos;

namespace ManagementConsole.Api.Services;

public sealed class DeploymentRepository
{
    private readonly Container _container;

    public DeploymentRepository(CosmosFactory factory) => _container = factory.Deployments;

    // Existing Cosmos records were written with the old CamelCase serializer
    // which mangled dictionary keys (OWNER → oWNER). New records use the
    // STJ-based serializer which preserves keys, but legacy records still
    // have mangled keys. Normalise all parameter keys to UPPER on read so
    // every consumer (UI, lockdown checks, worker launch) sees one schema.
    private static Deployment Normalize(Deployment d)
    {
        if (d.Parameters is { Count: > 0 } p)
        {
            d.Parameters = p.ToDictionary(
                kv => kv.Key.ToUpperInvariant(),
                kv => kv.Value,
                StringComparer.Ordinal);
        }
        return d;
    }

    public async Task<Deployment> CreateAsync(Deployment d, CancellationToken ct = default)
    {
        var resp = await _container.CreateItemAsync(d, new PartitionKey(d.CustomerId), cancellationToken: ct);
        return Normalize(resp.Resource);
    }

    public async Task<Deployment?> GetAsync(string id, string customerId, CancellationToken ct = default)
    {
        try
        {
            var resp = await _container.ReadItemAsync<Deployment>(id, new PartitionKey(customerId), cancellationToken: ct);
            return Normalize(resp.Resource);
        }
        catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task<List<Deployment>> ListByCustomerAsync(string customerId, CancellationToken ct = default)
    {
        var query = new QueryDefinition("SELECT * FROM c WHERE c.customerId = @cid ORDER BY c.createdAt DESC")
            .WithParameter("@cid", customerId);
        var iterator = _container.GetItemQueryIterator<Deployment>(query, requestOptions: new QueryRequestOptions
        {
            PartitionKey = new PartitionKey(customerId)
        });
        var results = new List<Deployment>();
        while (iterator.HasMoreResults)
        {
            foreach (var d in (await iterator.ReadNextAsync(ct)).Resource) results.Add(Normalize(d));
        }
        return results;
    }

    public Task<Deployment> UpdateAsync(Deployment d, CancellationToken ct = default) =>
        _container.ReplaceItemAsync(d, d.Id, new PartitionKey(d.CustomerId), cancellationToken: ct)
                  .ContinueWith(t => Normalize(t.Result.Resource), ct);

    public async Task<bool> HasInFlightAsync(string customerId, string envName, CancellationToken ct = default)
    {
        var query = new QueryDefinition(
            "SELECT VALUE COUNT(1) FROM c WHERE c.customerId = @cid AND c.environmentName = @env AND (c.status = 'Queued' OR c.status = 'Running')")
            .WithParameter("@cid", customerId).WithParameter("@env", envName);
        var iter = _container.GetItemQueryIterator<int>(query, requestOptions: new QueryRequestOptions
        {
            PartitionKey = new PartitionKey(customerId)
        });
        var resp = await iter.ReadNextAsync(ct);
        return resp.Resource.FirstOrDefault() > 0;
    }
}
