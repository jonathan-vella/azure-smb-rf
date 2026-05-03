using System.Text;
using Azure;
using Azure.Identity;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Blobs.Specialized;

namespace ManagementConsole.Api.Services;

/// <summary>
/// Persists worker log lines to an append blob per deployment. The SPA
/// terminal renders the blob via a cursor-based GET endpoint and polls for
/// new lines every few seconds, so the blob is the single source of truth
/// for both running and finished deployments \u2014 there is no live channel
/// to keep in sync.
///
/// Layout: container <c>app-data</c>, blob <c>logs/{customerId}/{deploymentId}.log</c>.
/// </summary>
public sealed class DeploymentLogStore
{
    private const string ContainerName = "app-data";
    private const string Prefix = "logs";

    // Append blobs cap at 50,000 blocks; each AppendBlock is one block. Batch
    // many lines into a single block to keep us well under that cap for long
    // deployments.
    private static readonly UTF8Encoding Utf8NoBom = new(encoderShouldEmitUTF8Identifier: false);

    private readonly BlobContainerClient? _container;
    private readonly ILogger<DeploymentLogStore> _log;

    public DeploymentLogStore(IConfiguration cfg, ILogger<DeploymentLogStore> log)
    {
        _log = log;
        var endpoint = cfg["Storage:BlobEndpoint"];
        if (string.IsNullOrWhiteSpace(endpoint))
        {
            _log.LogWarning("Storage:BlobEndpoint not configured — deployment log persistence disabled.");
            return;
        }

        var service = new BlobServiceClient(new Uri(endpoint), new DefaultAzureCredential());
        _container = service.GetBlobContainerClient(ContainerName);
    }

    public bool Enabled => _container is not null;

    public async Task AppendAsync(string customerId, string deploymentId, IEnumerable<string> lines, CancellationToken ct = default)
    {
        if (_container is null) return;
        var batch = string.Join('\n', lines) + "\n";
        if (batch.Length == 1) return;

        var blob = _container.GetAppendBlobClient(BlobPath(customerId, deploymentId));
        try
        {
            await blob.CreateIfNotExistsAsync(cancellationToken: ct);
            using var ms = new MemoryStream(Utf8NoBom.GetBytes(batch));
            await blob.AppendBlockAsync(ms, cancellationToken: ct);
        }
        catch (RequestFailedException ex)
        {
            _log.LogWarning(ex, "Failed to append {Count} log line(s) for deployment {Deployment}",
                lines.Count(), deploymentId);
        }
    }

    public async Task<string?> ReadAsync(string customerId, string deploymentId, CancellationToken ct = default)
    {
        if (_container is null) return null;
        var blob = _container.GetBlobClient(BlobPath(customerId, deploymentId));
        try
        {
            var resp = await blob.DownloadContentAsync(ct);
            return resp.Value.Content.ToString();
        }
        catch (RequestFailedException ex) when (ex.Status == 404)
        {
            return null;
        }
    }

    private static string BlobPath(string customerId, string deploymentId)
        => $"{Prefix}/{customerId}/{deploymentId}.log";
}
