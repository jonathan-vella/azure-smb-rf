using ManagementConsole.Api.Models;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;

namespace ManagementConsole.Api.Services;

/// <summary>
/// Single-doc settings store. The partner-wide configuration lives at
/// id="app" (partition key /id). When the doc is absent, defaults are
/// served from <see cref="PrerequisitesOptions"/> (i.e. the values baked into
/// the API container by main.bicep) so the API works on a fresh deploy
/// before anyone has saved settings.
/// </summary>
public sealed class SettingsRepository
{
    public const string DocId = "app";
    private readonly Container _container;
    private readonly IOptionsMonitor<PrerequisitesOptions> _prereqOptions;
    private readonly IConfiguration _cfg;

    private AppSettings? _cache;
    private DateTimeOffset _cacheExpires;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public SettingsRepository(
        CosmosFactory factory,
        IOptionsMonitor<PrerequisitesOptions> prereqOptions,
        IConfiguration cfg)
    {
        _container = factory.Settings;
        _prereqOptions = prereqOptions;
        _cfg = cfg;
    }

    public async Task<AppSettings> GetAsync(CancellationToken ct = default)
    {
        if (_cache is not null && DateTimeOffset.UtcNow < _cacheExpires) return _cache;
        await _gate.WaitAsync(ct);
        try
        {
            if (_cache is not null && DateTimeOffset.UtcNow < _cacheExpires) return _cache;
            AppSettings doc;
            try
            {
                var resp = await _container.ReadItemAsync<AppSettings>(
                    DocId, new PartitionKey(DocId), cancellationToken: ct);
                doc = resp.Resource;
                doc.ETag = resp.ETag;
            }
            catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
            {
                doc = Defaults();
            }
            // Backfill blanks with appsettings defaults so partial docs are usable.
            if (string.IsNullOrWhiteSpace(doc.RepoUrl)) doc.RepoUrl = DefaultRepoUrl();
            if (string.IsNullOrWhiteSpace(doc.RepoRef)) doc.RepoRef = _prereqOptions.CurrentValue.TemplateSource.Tag;
            _cache = doc;
            _cacheExpires = DateTimeOffset.UtcNow.AddSeconds(30);
            return doc;
        }
        finally { _gate.Release(); }
    }

    public async Task<AppSettings> UpsertAsync(AppSettings s, CancellationToken ct = default)
    {
        s.Id = DocId;
        s.UpdatedAt = DateTimeOffset.UtcNow;
        var options = s.ETag is null ? null : new ItemRequestOptions { IfMatchEtag = s.ETag };
        try
        {
            var resp = await _container.UpsertItemAsync(s, new PartitionKey(DocId), options, ct);
            var saved = resp.Resource;
            saved.ETag = resp.ETag;
            _cache = saved;
            _cacheExpires = DateTimeOffset.UtcNow.AddSeconds(30);
            return saved;
        }
        catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            // The 'settings' container itself is missing (404 on the
            // collection, not the item). This means the Cosmos account was
            // provisioned before the settings container was added to
            // main.bicep. Re-run `azd provision` to reconcile, or create the
            // container manually with /id as the partition key.
            throw new InvalidOperationException(
                "The Cosmos 'settings' container does not exist on this account. " +
                "Run `azd provision` against this environment to create it, or create " +
                $"the container manually (database 'console', container 'settings', partition key '/id'). " +
                $"Underlying error: {ex.Message}", ex);
        }
    }

    private AppSettings Defaults() => new()
    {
        Id = DocId,
        RepoUrl = DefaultRepoUrl(),
        RepoRef = _prereqOptions.CurrentValue.TemplateSource.Tag,
    };

    private string DefaultRepoUrl()
    {
        // Prefer explicit Repo:Url env (set by main.bicep), else derive from
        // the GitHub slug used by PrerequisitesTemplateService.
        var fromCfg = _cfg["Repo:Url"];
        if (!string.IsNullOrWhiteSpace(fromCfg)) return fromCfg!;
        var slug = _prereqOptions.CurrentValue.TemplateSource.Repo;
        return $"https://github.com/{slug}.git";
    }

    /// <summary>Repo slug owner/name extracted from the configured RepoUrl.</summary>
    public static string SlugFromUrl(string repoUrl)
    {
        var u = repoUrl.Trim();
        if (u.EndsWith(".git", StringComparison.OrdinalIgnoreCase)) u = u[..^4];
        var marker = "github.com/";
        var idx = u.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
        return idx >= 0 ? u[(idx + marker.Length)..].Trim('/') : u;
    }
}
