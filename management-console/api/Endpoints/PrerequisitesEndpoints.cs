using ManagementConsole.Api.Auth;
using ManagementConsole.Api.Models;
using ManagementConsole.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace ManagementConsole.Api.Endpoints;

/// <summary>
/// Customer-prerequisites endpoints (management group + policy initiative)
/// plus product-level template-fetch endpoints used by the SPA when it
/// orchestrates the customer-admin-driven MG deployment.
///
/// Lighthouse delegations are sub/RG-scoped — they cannot grant the partner
/// tenant rights to create management groups or assign MG-scoped policies in
/// the customer tenant. So the SPA executes these deployments under the
/// customer admin's own ARM token (acquired via popup from the Prerequisites
/// page). This API only:
///
///  1. Serves the ARM template fetched from the configured GitHub release.
///  2. Records the prerequisites deployment outcome on the customer document.
/// </summary>
public static class PrerequisitesEndpoints
{
    public static void MapPrerequisitesEndpoints(this IEndpointRouteBuilder app)
    {
        var pub = app.MapGroup("/prerequisites")
            .RequireAuthorization(Policies.PartnerStaff)
            .WithTags("Prerequisites");

        pub.MapGet("/template", async (
            [FromQuery] bool? refresh,
            PrerequisitesTemplateService svc,
            CancellationToken ct) =>
        {
            try
            {
                var t = await svc.GetAsync(forceRefresh: refresh ?? false, ct);
                return Results.Ok(new
                {
                    version = t.Version,
                    sourceRepo = t.SourceRepo,
                    templatePath = t.TemplatePath,
                    template = t.Template,
                });
            }
            catch (Exception ex)
            {
                return Results.Problem(
                    title: "Prerequisites template fetch failed",
                    detail: ex.Message,
                    statusCode: StatusCodes.Status502BadGateway);
            }
        });

        pub.MapGet("/policy-template", async (
            [FromQuery] bool? refresh,
            PrerequisitesTemplateService svc,
            CancellationToken ct) =>
        {
            try
            {
                var t = await svc.GetPolicyAsync(forceRefresh: refresh ?? false, ct);
                return Results.Ok(new
                {
                    version = t.Version,
                    sourceRepo = t.SourceRepo,
                    templatePath = t.TemplatePath,
                    template = t.Template,
                });
            }
            catch (Exception ex)
            {
                return Results.Problem(
                    title: "Prerequisites policy template fetch failed",
                    detail: ex.Message,
                    statusCode: StatusCodes.Status502BadGateway);
            }
        });

        // Sub-scope onboarding template that pre-creates the UAMI for the
        // smb-backup-02 DINE policy. Deployed by the customer admin during
        // onboarding because the partner UAMI cannot grant the required
        // sub-scope role assignments via Lighthouse.
        pub.MapGet("/policy-mi-template", async (
            [FromQuery] bool? refresh,
            PrerequisitesTemplateService svc,
            CancellationToken ct) =>
        {
            try
            {
                var t = await svc.GetPolicyMiAsync(forceRefresh: refresh ?? false, ct);
                return Results.Ok(new
                {
                    version = t.Version,
                    sourceRepo = t.SourceRepo,
                    templatePath = t.TemplatePath,
                    template = t.Template,
                });
            }
            catch (Exception ex)
            {
                return Results.Problem(
                    title: "Policy MI onboarding template fetch failed",
                    detail: ex.Message,
                    statusCode: StatusCodes.Status502BadGateway);
            }
        });

        var perCustomer = app.MapGroup("/customers/{id}/prerequisites")
            .RequireAuthorization(Policies.PartnerStaff)
            .WithTags("Prerequisites");

        // Persist the outcome of an MG deployment (interactive or offline).
        perCustomer.MapPost("/", async (
            string id,
            [FromQuery] string tenantId,
            [FromBody] RecordPrerequisitesRequest body,
            CustomerRepository repo,
            CancellationToken ct) =>
        {
            var customer = await repo.GetAsync(id, tenantId, ct);
            if (customer is null) return Results.NotFound();

            // Always include "global" — many ARM resources (role assignments,
            // policy assignments, etc.) report region "global" and would be
            // blocked otherwise.
            var regions = NormalizeRegions(body.AllowedRegions ?? customer.Prerequisites?.AllowedRegions);

            customer.Prerequisites = new PrerequisitesState(
                ManagementGroupId: body.ManagementGroupId,
                TemplateVersion: body.TemplateVersion,
                LastDeploymentName: body.DeploymentName,
                CorrelationId: body.CorrelationId,
                DeployedAt: body.Status == "Succeeded" ? DateTimeOffset.UtcNow : customer.Prerequisites?.DeployedAt,
                Status: body.Status,
                AllowedRegions: regions);

            // The policy-MI deployment runs as part of the same Prerequisites
            // flow (sub-scope, customer-admin token). Persist its resource id
            // when supplied so the worker can wire the UAMI into smb-backup-02.
            if (!string.IsNullOrWhiteSpace(body.PolicyMiResourceId))
            {
                customer.PolicyMiResourceId = body.PolicyMiResourceId!;
            }

            var saved = await repo.UpsertAsync(customer, ct);
            return Results.Ok(saved);
        });

        // Update only the allowed-regions list. Used by the prerequisites manage
        // page when the operator widens / narrows the list and re-deploys
        // the policy initiative interactively.
        perCustomer.MapPut("/allowed-regions", async (
            string id,
            [FromQuery] string tenantId,
            [FromBody] UpdateAllowedRegionsRequest body,
            CustomerRepository repo,
            CancellationToken ct) =>
        {
            var customer = await repo.GetAsync(id, tenantId, ct);
            if (customer is null) return Results.NotFound();
            if (customer.Prerequisites is null)
            {
                return Results.BadRequest(new { error = "Prerequisites not deployed yet" });
            }
            var regions = NormalizeRegions(body.AllowedRegions);
            customer.Prerequisites = customer.Prerequisites with { AllowedRegions = regions };
            var saved = await repo.UpsertAsync(customer, ct);
            return Results.Ok(saved);
        });
    }

    private static List<string> NormalizeRegions(IEnumerable<string>? input)
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (input is not null)
        {
            foreach (var r in input)
            {
                if (!string.IsNullOrWhiteSpace(r)) set.Add(r.Trim().ToLowerInvariant());
            }
        }
        set.Add("global");
        return set.OrderBy(x => x, StringComparer.Ordinal).ToList();
    }

    public sealed record RecordPrerequisitesRequest(
        string ManagementGroupId,
        string TemplateVersion,
        string DeploymentName,
        string? CorrelationId,
        string Status, // Pending | Succeeded | Failed
        List<string>? AllowedRegions = null,
        string? PolicyMiResourceId = null);

    public sealed record UpdateAllowedRegionsRequest(List<string> AllowedRegions);
}
