using System.Diagnostics;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace ManagementConsole.Api.Services;

/// <summary>
/// Configuration for the prerequisites template source. Bicep sources are
/// fetched from a GitHub zipball and compiled on demand by the bicep CLI
/// bundled in the API image, so partners can pin to a specific version
/// without redeploying the console and the repo no longer ships compiled
/// ARM JSON. Defaults point at <c>jonathan-vella/azure-smb-rf@main</c>,
/// with the MG-creation template <c>deploy-mg.bicep</c>.
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
    /// Path inside the zipball to the MG-creation Bicep template. Compiled
    /// to ARM JSON in-process via the bundled <c>bicep</c> CLI.
    /// </summary>
    public string TemplatePath { get; set; } = "infra/bicep/smb-ready-foundation/deploy-mg.bicep";

    /// <summary>
    /// Path inside the zipball to the MG-scoped policy initiative Bicep
    /// template. Deployed against the newly-created <c>smb-rf</c> MG
    /// immediately after <see cref="TemplatePath"/>.
    /// </summary>
    public string PolicyTemplatePath { get; set; } = "infra/bicep/smb-ready-foundation/modules/policy-assignments-mg-initiative.bicep";

    /// <summary>
    /// Path to the customer-onboarding sub-scope template that pre-creates a
    /// User-Assigned Managed Identity for the smb-backup-02 DINE policy and
    /// grants it Backup/VM Contributor at subscription scope. Deployed by the
    /// customer admin during onboarding (the partner UAMI cannot grant these
    /// roles via Lighthouse).
    /// </summary>
    public string PolicyMiTemplatePath { get; set; } = "management-console/infra/onboarding/policy-mi.bicep";

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

        // 2. Recursively fetch the requested .bicep file plus its module
        // dependencies into a temp working directory mirroring repo layout.
        // Using raw.githubusercontent.com is dramatically faster than the
        // multi-MB zipball — typically 2-3 small file downloads instead of
        // ~5 MB. Module references are resolved from `module x 'rel/path.bicep'`
        // declarations.
        var workDir = Path.Combine(Path.GetTempPath(), "smb-rf-prereq", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(workDir);
        try
        {
            var fetched = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            await FetchBicepRecursiveAsync(http, opts, resolvedTag, NormalizePath(templatePath), workDir, fetched, ct);
            _log.LogInformation(
                "Fetched {Count} bicep file(s) for {Path} @ {Tag}; compiling…",
                fetched.Count, templatePath, resolvedTag);

            // 3. Compile with the bundled bicep CLI.
            var localBicepPath = Path.Combine(workDir, NormalizePath(templatePath).Replace('/', Path.DirectorySeparatorChar));
            var compiledJson = await RunBicepBuildAsync(localBicepPath, ct);
            using var doc = JsonDocument.Parse(compiledJson);
            var template = doc.RootElement.Clone();

            return new PrerequisitesTemplate(
                Version: resolvedTag,
                SourceRepo: opts.Repo,
                TemplatePath: templatePath,
                Template: template);
        }
        finally
        {
            try { Directory.Delete(workDir, recursive: true); } catch { /* best-effort cleanup */ }
        }
    }

    // Pattern: `module <symbol> '<relative-path>.bicep' = ...` — captures
    // the relative path. We deliberately ignore registry references
    // (`br/public:...`) and bicep-module aliases (`br:...`).
    private static readonly System.Text.RegularExpressions.Regex ModuleRefRegex = new(
        @"^\s*module\s+\w+\s+'((?!br[/:])[^']+\.bicep)'",
        System.Text.RegularExpressions.RegexOptions.Compiled |
        System.Text.RegularExpressions.RegexOptions.Multiline);

    private async Task FetchBicepRecursiveAsync(
        HttpClient http,
        PrerequisitesTemplateSource opts,
        string resolvedTag,
        string repoRelativePath,
        string workDir,
        HashSet<string> fetched,
        CancellationToken ct)
    {
        if (!fetched.Add(repoRelativePath)) return;

        var rawUrl = $"https://raw.githubusercontent.com/{opts.Repo}/{Uri.EscapeDataString(resolvedTag)}/{repoRelativePath}";
        using var resp = await http.GetAsync(rawUrl, ct);
        if (!resp.IsSuccessStatusCode)
        {
            if (resp.StatusCode == System.Net.HttpStatusCode.NotFound)
            {
                throw new InvalidOperationException(
                    $"Bicep file '{repoRelativePath}' was not found at ref '{resolvedTag}' of repo '{opts.Repo}'. " +
                    $"Open the management console's Settings page and verify that 'Repository URL' and " +
                    $"'Repository ref' point at a branch or release that contains this file " +
                    $"(the default 'jonathan-vella/azure-smb-rf@main' does). If you are using a fork, " +
                    $"either merge the latest upstream changes or switch the ref to a branch/tag that includes it.");
            }
            throw new InvalidOperationException(
                $"Failed to download {rawUrl}: {(int)resp.StatusCode} {resp.ReasonPhrase}");
        }

        var content = await resp.Content.ReadAsStringAsync(ct);
        var localPath = Path.Combine(workDir, repoRelativePath.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(localPath)!);
        await File.WriteAllTextAsync(localPath, content, ct);

        // Resolve module references relative to the current file's directory,
        // re-rooted at the repo. Skip registry references.
        var currentDir = Path.GetDirectoryName(repoRelativePath.Replace('\\', '/'))?.Replace('\\', '/') ?? string.Empty;
        foreach (System.Text.RegularExpressions.Match m in ModuleRefRegex.Matches(content))
        {
            var relRef = m.Groups[1].Value.Replace('\\', '/');
            var combined = string.IsNullOrEmpty(currentDir) ? relRef : currentDir + "/" + relRef;
            var resolved = NormalizePath(combined);
            await FetchBicepRecursiveAsync(http, opts, resolvedTag, resolved, workDir, fetched, ct);
        }
    }

    // Collapse "a/b/../c" segments into "a/c" so HashSet de-duplicates and the
    // local filesystem layout stays clean.
    private static string NormalizePath(string path)
    {
        var parts = path.Replace('\\', '/').TrimStart('/').Split('/');
        var stack = new Stack<string>();
        foreach (var p in parts)
        {
            if (p == "." || p.Length == 0) continue;
            if (p == ".." && stack.Count > 0) { stack.Pop(); continue; }
            stack.Push(p);
        }
        return string.Join('/', stack.Reverse());
    }

    private async Task<string> RunBicepBuildAsync(string bicepFilePath, CancellationToken ct)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "bicep",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = Path.GetDirectoryName(bicepFilePath)!,
        };
        psi.ArgumentList.Add("build");
        psi.ArgumentList.Add("--stdout");
        psi.ArgumentList.Add(bicepFilePath);
        // Bicep is a managed .NET app and fails on systems without ICU
        // (libicu). Compiling templates doesn't need locale-aware string
        // operations, so run it in invariant globalization mode. This
        // affects the bicep subprocess only — the API host is unaffected.
        psi.Environment["DOTNET_SYSTEM_GLOBALIZATION_INVARIANT"] = "1";

        using var proc = new Process { StartInfo = psi };
        try { proc.Start(); }
        catch (System.ComponentModel.Win32Exception ex)
        {
            throw new InvalidOperationException(
                "The 'bicep' CLI was not found on PATH. The management-console API image must " +
                "include the bicep CLI (see management-console/api/Dockerfile).", ex);
        }

        var stdoutTask = proc.StandardOutput.ReadToEndAsync(ct);
        var stderrTask = proc.StandardError.ReadToEndAsync(ct);
        await proc.WaitForExitAsync(ct);
        var stdout = await stdoutTask;
        var stderr = await stderrTask;

        if (proc.ExitCode != 0)
        {
            throw new InvalidOperationException(
                $"bicep build failed (exit {proc.ExitCode}) for '{bicepFilePath}':{Environment.NewLine}{stderr}");
        }
        if (!string.IsNullOrWhiteSpace(stderr))
        {
            // Warnings only (e.g. BCP187) — log but don't fail.
            _log.LogInformation("bicep build warnings for {File}: {Stderr}", bicepFilePath, stderr.Trim());
        }
        return stdout;
    }
}
