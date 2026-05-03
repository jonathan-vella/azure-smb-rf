using System.IO.Compression;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace ManagementConsole.Api.Services;

/// <summary>
/// Configuration for the prerequisites template source. Templates are
/// fetched from a GitHub release zipball, NOT bundled with the API, so
/// partners can pin to a specific version without redeploying the console.
/// Defaults point at <c>jonathan-vella/azure-smb-rf</c>'s latest release,
/// with the MG-creation template <c>deploy-mg.json</c>.
///
/// Note: the upstream artifact in the repo is called "SMB Ready Foundation";
/// these templates are the prerequisites that must be deployed in the
/// customer tenant before scenarios can run.
/// </summary>
public sealed class PrerequisitesOptions
{
    public const string SectionName = "Prerequisites";

    public PrerequisitesTemplateSource TemplateSource { get; set; } = new();
}

public sealed class PrerequisitesTemplateSource
{
    /// <summary>GitHub repo in <c>owner/name</c> form.</summary>
    public string Repo { get; set; } = "jonathan-vella/azure-smb-rf";

    /// <summary>Release tag, branch, or commit SHA. Use "latest" to resolve the latest release via the GitHub API.</summary>
    public string Tag { get; set; } = "main";

    /// <summary>
    /// Path inside the release zipball to the ARM JSON template (the file
    /// produced by <c>az bicep build</c> from <c>deploy-mg.bicep</c>).
    /// </summary>
    public string TemplatePath { get; set; } = "infra/bicep/smb-ready-foundation/deploy-mg.json";

    /// <summary>
    /// Path inside the release zipball to the MG-scoped policy initiative
    /// template (compiled from <c>policy-assignments-mg-initiative.bicep</c>).
    /// Deployed against the newly-created <c>smb-rf</c> MG immediately after
    /// <see cref="TemplatePath"/>.
    /// </summary>
    public string PolicyTemplatePath { get; set; } = "infra/bicep/smb-ready-foundation/modules/policy-assignments-mg-initiative.json";

    /// <summary>
    /// Path to the customer-onboarding sub-scope template that pre-creates a
    /// User-Assigned Managed Identity for the smb-backup-02 DINE policy and
    /// grants it Backup/VM Contributor at subscription scope. Deployed by the
    /// customer admin during onboarding (the partner UAMI cannot grant these
    /// roles via Lighthouse). Compiled from
    /// <c>management-console/infra/onboarding/policy-mi.bicep</c>.
    /// </summary>
    public string PolicyMiTemplatePath { get; set; } = "management-console/infra/onboarding/policy-mi.json";

    /// <summary>How long to cache the resolved template before re-fetching.</summary>
    public int CacheMinutes { get; set; } = 60;

    /// <summary>Optional GitHub PAT for higher rate limits / private repos.</summary>
    public string? GitHubToken { get; set; }
}

public sealed record PrerequisitesTemplate(
    string Version,
    string SourceRepo,
    string TemplatePath,
    JsonElement Template);

/// <summary>
/// Resolves the prerequisites ARM templates from a GitHub release.
/// </summary>
public sealed class PrerequisitesTemplateService
{
    private static readonly ProductInfoHeaderValue UserAgent =
        new("smb-rf-management-console", "1.0");

    private readonly IHttpClientFactory _httpFactory;
    private readonly IOptionsMonitor<PrerequisitesOptions> _options;
    private readonly SettingsRepository _settings;
    private readonly ILogger<PrerequisitesTemplateService> _log;

    private readonly SemaphoreSlim _gate = new(1, 1);

    public PrerequisitesTemplateService(
        IHttpClientFactory httpFactory,
        IOptionsMonitor<PrerequisitesOptions> options,
        SettingsRepository settings,
        ILogger<PrerequisitesTemplateService> log)
    {
        _httpFactory = httpFactory;
        _options = options;
        _settings = settings;
        _log = log;
    }

    // Caching disabled by design: the API container is long-lived and only
    // redeployed on code changes, but the prerequisites templates on the
    // configured REPO_REF can move at any time. Every customer-facing
    // operation (onboarding, MG creation, policy assignment, redeploy) must
    // see the current version, so we always fetch from GitHub.
    public Task<PrerequisitesTemplate> GetAsync(bool forceRefresh = false, CancellationToken ct = default)
        => GetByPathAsync(_options.CurrentValue.TemplateSource.TemplatePath, ct);

    public Task<PrerequisitesTemplate> GetPolicyAsync(bool forceRefresh = false, CancellationToken ct = default)
        => GetByPathAsync(_options.CurrentValue.TemplateSource.PolicyTemplatePath, ct);

    public Task<PrerequisitesTemplate> GetPolicyMiAsync(bool forceRefresh = false, CancellationToken ct = default)
        => GetByPathAsync(_options.CurrentValue.TemplateSource.PolicyMiTemplatePath, ct);

    private async Task<PrerequisitesTemplate> GetByPathAsync(string path, CancellationToken ct)
    {
        var opts = _options.CurrentValue.TemplateSource;
        // Settings doc overrides the appsettings repo/tag so partners can
        // re-target without redeploying the API.
        var settings = await _settings.GetAsync(ct);
        var effective = new PrerequisitesTemplateSource
        {
            Repo = SettingsRepository.SlugFromUrl(settings.RepoUrl),
            Tag = settings.RepoRef,
            TemplatePath = opts.TemplatePath,
            PolicyTemplatePath = opts.PolicyTemplatePath,
            PolicyMiTemplatePath = opts.PolicyMiTemplatePath,
            CacheMinutes = opts.CacheMinutes,
            GitHubToken = opts.GitHubToken,
        };
        // Single-flight gate so concurrent callers don't all hammer GitHub at
        // the same time, but no cross-request reuse: each acquirer issues its
        // own fetch.
        await _gate.WaitAsync(ct);
        try
        {
            return await FetchAsync(effective, path, ct);
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task<PrerequisitesTemplate> FetchAsync(PrerequisitesTemplateSource opts, string templatePath, CancellationToken ct)
    {
        var http = _httpFactory.CreateClient("github");
        http.DefaultRequestHeaders.UserAgent.Clear();
        http.DefaultRequestHeaders.UserAgent.Add(UserAgent);
        http.DefaultRequestHeaders.Accept.Clear();
        http.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        if (!string.IsNullOrWhiteSpace(opts.GitHubToken))
        {
            http.DefaultRequestHeaders.Authorization =
                new AuthenticationHeaderValue("Bearer", opts.GitHubToken);
        }

        // 1. Resolve tag to concrete version (handles "latest").
        string resolvedTag;
        if (string.Equals(opts.Tag, "latest", StringComparison.OrdinalIgnoreCase))
        {
            var url = $"https://api.github.com/repos/{opts.Repo}/releases/latest";
            using var resp = await http.GetAsync(url, ct);
            if (!resp.IsSuccessStatusCode)
            {
                throw new InvalidOperationException(
                    $"GitHub releases lookup failed for {opts.Repo}: {(int)resp.StatusCode} {resp.ReasonPhrase}");
            }
            var release = await resp.Content.ReadFromJsonAsync<JsonElement>(cancellationToken: ct);
            resolvedTag = release.GetProperty("tag_name").GetString()
                ?? throw new InvalidOperationException("GitHub release has no tag_name.");
        }
        else
        {
            resolvedTag = opts.Tag;
        }

        // 2. Download the zipball. The /zipball/{ref} endpoint works for
        // tags, branches, and commit SHAs and redirects to codeload.
        var zipUrl = $"https://api.github.com/repos/{opts.Repo}/zipball/{Uri.EscapeDataString(resolvedTag)}";
        _log.LogInformation("Fetching prerequisites template from {Url}", zipUrl);

        // Don't keep the previous Accept header on the binary download.
        http.DefaultRequestHeaders.Accept.Clear();
        using var zipResp = await http.GetAsync(zipUrl, HttpCompletionOption.ResponseHeadersRead, ct);
        if (!zipResp.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(
                $"Failed to download release zip {zipUrl}: {(int)zipResp.StatusCode} {zipResp.ReasonPhrase}");
        }

        await using var zipStream = await zipResp.Content.ReadAsStreamAsync(ct);
        // ZipArchive needs a seekable stream.
        using var ms = new MemoryStream();
        await zipStream.CopyToAsync(ms, ct);
        ms.Position = 0;

        using var archive = new ZipArchive(ms, ZipArchiveMode.Read);

        // GitHub zipballs nest everything under a top-level "<repo>-<tag>/"
        // folder. Match the entry by suffix instead of computing the prefix.
        var suffix = "/" + templatePath.Replace('\\', '/').TrimStart('/');
        var entry = archive.Entries.FirstOrDefault(e =>
            e.FullName.Replace('\\', '/').EndsWith(suffix, StringComparison.OrdinalIgnoreCase));
        if (entry is null)
        {
            // Most common cause: the configured RepoUrl / RepoRef (in the
            // console's Settings page) points at a fork or branch that
            // doesn't contain this template yet — for example, the upstream
            // 'main' before the management-console onboarding templates were
            // merged. Give the operator a clear, actionable message instead
            // of a bare "not found".
            throw new InvalidOperationException(
                $"Template '{templatePath}' was not found at ref '{resolvedTag}' of repo '{opts.Repo}'. " +
                $"Open the management console's Settings page and verify that 'Repository URL' and " +
                $"'Repository ref' point at a branch or release that contains this file " +
                $"(the default 'jonathan-vella/azure-smb-rf@main' does). If you are using a fork, " +
                $"either merge the latest upstream changes or switch the ref to a branch/tag that includes it.");
        }

        await using var entryStream = entry.Open();
        using var doc = await JsonDocument.ParseAsync(entryStream, cancellationToken: ct);
        // Clone so the document can be disposed.
        var template = doc.RootElement.Clone();

        return new PrerequisitesTemplate(
            Version: resolvedTag,
            SourceRepo: opts.Repo,
            TemplatePath: templatePath,
            Template: template);
    }
}
