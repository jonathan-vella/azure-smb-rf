using ManagementConsole.Api.Models;
using Microsoft.Azure.Cosmos;

namespace ManagementConsole.Api.Services;

public sealed class CustomerRepository
{
    private readonly Container _container;

    public CustomerRepository(CosmosFactory factory) => _container = factory.Customers;

    public async Task<Customer?> GetAsync(string id, string tenantId, CancellationToken ct = default)
    {
        try
        {
            var resp = await _container.ReadItemAsync<Customer>(id, new PartitionKey(tenantId), cancellationToken: ct);
            var c = resp.Resource;
            c.ETag = resp.ETag;
            return c;
        }
        catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task<List<Customer>> ListAsync(CancellationToken ct = default)
    {
        var iterator = _container.GetItemQueryIterator<Customer>("SELECT * FROM c");
        var results = new List<Customer>();
        while (iterator.HasMoreResults) results.AddRange((await iterator.ReadNextAsync(ct)).Resource);
        return results;
    }

    /// <summary>
    /// Find a customer by its Azure subscription id (cross-partition query).
    /// Used to block duplicate onboarding of the same subscription.
    /// </summary>
    public async Task<Customer?> FindBySubscriptionAsync(string subscriptionId, CancellationToken ct = default)
    {
        var query = new QueryDefinition("SELECT * FROM c WHERE c.subscriptionId = @sub")
            .WithParameter("@sub", subscriptionId);
        var iterator = _container.GetItemQueryIterator<Customer>(query);
        while (iterator.HasMoreResults)
        {
            var page = await iterator.ReadNextAsync(ct);
            var first = page.Resource.FirstOrDefault();
            if (first is not null) return first;
        }
        return null;
    }

    public async Task<bool> DeleteAsync(string id, string tenantId, CancellationToken ct = default)
    {
        try
        {
            await _container.DeleteItemAsync<Customer>(id, new PartitionKey(tenantId), cancellationToken: ct);
            return true;
        }
        catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return false;
        }
    }

    public async Task<Customer> UpsertAsync(Customer customer, CancellationToken ct = default)
    {
        customer.UpdatedAt = DateTimeOffset.UtcNow;
        var options = customer.ETag is null ? null : new ItemRequestOptions { IfMatchEtag = customer.ETag };
        var resp = await _container.UpsertItemAsync(customer, new PartitionKey(customer.TenantId), options, ct);
        var c = resp.Resource;
        c.ETag = resp.ETag;
        return c;
    }
}
