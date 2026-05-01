namespace ManagementConsole.Api.Models;

public enum DeploymentStatus { Queued, Running, Succeeded, Failed, Cancelled }

public enum Scenario { Baseline, Firewall, Vpn, Full }

public sealed record CustomerEnvironment(
    string Name,
    Scenario? Scenario,
    Dictionary<string, string>? Parameters,
    string? LastDeploymentId);

public sealed class Customer
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string TenantId { get; set; } = "";              // Cosmos partition key
    public string SubscriptionId { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public string ManagedByTenantId { get; set; } = "";     // Partner tenant
    public string LighthouseRegistrationId { get; set; } = "";
    /// <summary>
    /// Resource id of the customer-tenant UAMI created during onboarding for
    /// the smb-backup-02 DINE policy. Forwarded to the worker as
    /// <c>POLICY_MI_RESOURCE_ID</c> and into the prerequisites deployment as
    /// <c>policyMiResourceId</c>. Empty when prerequisites were deployed before
    /// the policy-mi step shipped — in that case the deployment falls back to
    /// SystemAssigned and will fail the role-assignment writes (operator must
    /// re-deploy prerequisites or run the policy-mi template manually).
    /// </summary>
    public string PolicyMiResourceId { get; set; } = "";
    public List<CustomerEnvironment> Environments { get; set; } = new();
    public PrerequisitesState? Prerequisites { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
    public string? ETag { get; set; }
}

/// <summary>
/// Tracks the customer-side prerequisites deployment (management group +
/// policy initiative for the SMB Ready Foundation product). MG creation
/// cannot be Lighthouse-delegated, so this records the result of a deployment
/// the customer admin executed (interactively via the SPA, or offline via
/// the generated script).
/// </summary>
public sealed record PrerequisitesState(
    string? ManagementGroupId,
    string? TemplateVersion,
    string? LastDeploymentName,
    string? CorrelationId,
    DateTimeOffset? DeployedAt,
    string? Status, // Pending | Succeeded | Failed
    List<string>? AllowedRegions = null);

/// <summary>
/// Partner-wide application settings persisted in Cosmos as a single doc
/// with id="app" (partition key /id). Currently scopes the source repo for
/// foundation templates and the worker's deployment clone, so partners can
/// pin to a fork or feature branch without redeploying the console.
/// Falls back to <see cref="PrerequisitesOptions"/> defaults when absent.
/// </summary>
public sealed class AppSettings
{
    public string Id { get; set; } = "app";
    public string RepoUrl { get; set; } = "";
    public string RepoRef { get; set; } = "";
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
    public string? ETag { get; set; }
}

public sealed class Deployment
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string CustomerId { get; set; } = "";          // Cosmos partition key
    public string EnvironmentName { get; set; } = "";
    public Scenario Scenario { get; set; }
    public Dictionary<string, string> Parameters { get; set; } = new();
    public DeploymentStatus Status { get; set; } = DeploymentStatus.Queued;
    public string? JobExecutionName { get; set; }
    public string? FailureReason { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? StartedAt { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }
    public string CreatedBy { get; set; } = "";
}
