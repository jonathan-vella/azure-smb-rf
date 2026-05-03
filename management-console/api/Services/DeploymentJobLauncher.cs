using Azure.Core;
using Azure.Identity;
using Azure.ResourceManager;
using Azure.ResourceManager.AppContainers;
using Azure.ResourceManager.AppContainers.Models;
using ManagementConsole.Api.Models;

namespace ManagementConsole.Api.Services;

/// <summary>
/// Triggers a manual execution of the Container Apps Job that performs the
/// actual `azd up` against the customer subscription.
/// </summary>
public sealed class DeploymentJobLauncher
{
    private readonly IConfiguration _cfg;
    private readonly ArmClient _arm;
    private readonly TokenCredential _credential;
    private readonly HttpClient _http;
    private readonly SettingsRepository _settings;
    private readonly ILogger<DeploymentJobLauncher> _log;

    public DeploymentJobLauncher(IConfiguration cfg, IHttpClientFactory httpFactory, SettingsRepository settings, ILogger<DeploymentJobLauncher> log)
    {
        _cfg = cfg;
        _log = log;
        _credential = new DefaultAzureCredential();
        _arm = new ArmClient(_credential);
        _http = httpFactory.CreateClient("arm");
        _settings = settings;
    }

    public async Task<string> LaunchAsync(Deployment deployment, Customer customer, CancellationToken ct = default)
    {
        var subId = _cfg["WORKER_SUBSCRIPTION_ID"]
            ?? throw new InvalidOperationException("WORKER_SUBSCRIPTION_ID not set");
        var rg = _cfg["WORKER_RG"]
            ?? throw new InvalidOperationException("WORKER_RG not set");
        var jobName = _cfg["WORKER_JOB_NAME"]
            ?? throw new InvalidOperationException("WORKER_JOB_NAME not set");

        var jobId = ContainerAppJobResource.CreateResourceIdentifier(subId, rg, jobName);
        var job = _arm.GetContainerAppJobResource(jobId);

        // ARM requires every container in the override template to specify
        // an Image — it does not merge the override with the job definition's
        // container. Pull the configured image (and command/args) from the
        // job and pass them through verbatim so we only override env vars.
        var jobData = (await job.GetAsync(ct)).Value.Data;
        var baseContainer = jobData.Template?.Containers?.FirstOrDefault()
            ?? throw new InvalidOperationException(
                $"Container Apps Job '{jobName}' has no containers defined.");

        var workerContainer = new JobExecutionContainer
        {
            Name = "worker",
            Image = baseContainer.Image,
        };
        if (baseContainer.Resources is not null)
        {
            workerContainer.Resources = baseContainer.Resources;
        }
        foreach (var c in baseContainer.Command) workerContainer.Command.Add(c);
        foreach (var a in baseContainer.Args) workerContainer.Args.Add(a);
        // Carry over any env vars defined on the job (e.g. AZURE_CLIENT_ID
        // for the worker UAMI) before appending per-deployment overrides.
        foreach (var e in baseContainer.Env)
        {
            workerContainer.Env.Add(new ContainerAppEnvironmentVariable
            {
                Name = e.Name,
                Value = e.Value,
                SecretRef = e.SecretRef,
            });
        }
        // Override the source repo/ref with whatever is currently in app
        // settings, so the worker clones the same code the API serves
        // foundation templates from. Unconditional overwrite of any baked-in
        // job env values: the settings doc is the single source of truth.
        var settings = await _settings.GetAsync(ct);
        ReplaceOrAdd(workerContainer.Env, "REPO_URL", settings.RepoUrl);
        ReplaceOrAdd(workerContainer.Env, "REPO_REF", settings.RepoRef);
        // If the SPA chose a deployment region, forward it as AZURE_LOCATION
        // so `azd env new --location` and the bicep templates pick it up.
        if (deployment.Parameters.TryGetValue("LOCATION", out var loc) && !string.IsNullOrWhiteSpace(loc))
        {
            ReplaceOrAdd(workerContainer.Env, "AZURE_LOCATION", loc);
        }
        workerContainer.Env.Add(new ContainerAppEnvironmentVariable { Name = "CUSTOMER_ID", Value = customer.Id });
        workerContainer.Env.Add(new ContainerAppEnvironmentVariable { Name = "SUBSCRIPTION_ID", Value = customer.SubscriptionId });
        workerContainer.Env.Add(new ContainerAppEnvironmentVariable { Name = "ENV_NAME", Value = deployment.EnvironmentName });
        workerContainer.Env.Add(new ContainerAppEnvironmentVariable { Name = "SCENARIO", Value = deployment.Scenario.ToString().ToLowerInvariant() });
        workerContainer.Env.Add(new ContainerAppEnvironmentVariable { Name = "DEPLOYMENT_ID", Value = deployment.Id });
        workerContainer.Env.Add(new ContainerAppEnvironmentVariable
        {
            Name = "PARAMETERS_JSON",
            Value = System.Text.Json.JsonSerializer.Serialize(deployment.Parameters),
        });
        // Pre-created customer-tenant UAMI for the smb-backup-02 DINE policy.
        // Empty for customers onboarded before the policy-mi step shipped —
        // the worker omits the azd env var in that case and the foundation
        // falls back to SystemAssigned (which will fail role-assignment
        // writes via Lighthouse — operator must re-run the onboarding wizard
        // for that customer or deploy policy-mi.bicep manually).
        if (!string.IsNullOrWhiteSpace(customer.PolicyMiResourceId))
        {
            workerContainer.Env.Add(new ContainerAppEnvironmentVariable
            {
                Name = "POLICY_MI_RESOURCE_ID",
                Value = customer.PolicyMiResourceId,
            });
        }

        var template = new ContainerAppJobExecutionTemplate();
        template.Containers.Add(workerContainer);

        // WaitUntil.Started returns an LRO whose .Value isn't materialised
        // yet — accessing it throws "The operation has not completed yet".
        // The start LRO completes once the execution has been *scheduled*
        // (the job itself then runs asynchronously), so waiting for it is
        // cheap and gives us the execution name we need to track.
        var op = await job.StartAsync(Azure.WaitUntil.Completed, template, ct);
        var executionName = op.Value.Name;
        _log.LogInformation("Launched job execution {Execution} for deployment {Deployment}",
            executionName, deployment.Id);
        return executionName;
    }

    /// <summary>
    /// Stops a running job execution. Idempotent — returns false if the
    /// execution doesn't exist (e.g. already finished and reaped).
    /// The Azure SDK doesn't surface a typed Stop on JobExecutionResource,
    /// so we POST to the stop REST endpoint directly.
    /// </summary>
    public async Task<bool> StopExecutionAsync(string executionName, CancellationToken ct = default)
    {
        var subId = _cfg["WORKER_SUBSCRIPTION_ID"]
            ?? throw new InvalidOperationException("WORKER_SUBSCRIPTION_ID not set");
        var rg = _cfg["WORKER_RG"]
            ?? throw new InvalidOperationException("WORKER_RG not set");
        var jobName = _cfg["WORKER_JOB_NAME"]
            ?? throw new InvalidOperationException("WORKER_JOB_NAME not set");

        var url =
            $"https://management.azure.com/subscriptions/{subId}/resourceGroups/{rg}" +
            $"/providers/Microsoft.App/jobs/{jobName}/executions/{executionName}/stop" +
            "?api-version=2024-03-01";

        var token = await _credential.GetTokenAsync(
            new TokenRequestContext(new[] { "https://management.azure.com/.default" }), ct);
        using var req = new HttpRequestMessage(HttpMethod.Post, url);
        req.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token.Token);
        using var resp = await _http.SendAsync(req, ct);

        if (resp.StatusCode == System.Net.HttpStatusCode.NotFound) return false;
        if (!resp.IsSuccessStatusCode)
        {
            var body = await resp.Content.ReadAsStringAsync(ct);
            throw new InvalidOperationException(
                $"Stop execution returned {(int)resp.StatusCode}: {body}");
        }
        _log.LogInformation("Stop requested for job execution {Execution}", executionName);
        return true;
    }

    private static void ReplaceOrAdd(IList<ContainerAppEnvironmentVariable> env, string name, string value)
    {
        for (var i = env.Count - 1; i >= 0; i--)
        {
            if (string.Equals(env[i].Name, name, StringComparison.Ordinal)) env.RemoveAt(i);
        }
        env.Add(new ContainerAppEnvironmentVariable { Name = name, Value = value });
    }
}
