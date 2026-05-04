using ManagementConsole.Api.Auth;
using ManagementConsole.Api.Models;
using ManagementConsole.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace ManagementConsole.Api.Endpoints;

public static class CustomerEndpoints
{
    public static void MapCustomerEndpoints(this IEndpointRouteBuilder app)
    {
        // Top-level: list regions for an arbitrary subscription via the
        // partner UAMI. Used by the onboarding form (no customer record
        // yet) and as the data source for the customer-scoped variant.
        // When no subscriptionId is provided we fall back to the partner's
        // own management subscription (WORKER_SUBSCRIPTION_ID) — used by
        // the foundation onboarding flow before any Lighthouse delegation
        // is in place on the customer side.
        app.MapGet("/locations", async (
                [FromQuery] string? subscriptionId,
                IConfiguration cfg,
                LighthouseService lh,
                CancellationToken ct) =>
            {
                var sub = string.IsNullOrWhiteSpace(subscriptionId)
                    ? cfg["WORKER_SUBSCRIPTION_ID"]
                    : subscriptionId;
                if (string.IsNullOrWhiteSpace(sub))
                {
                    return Results.BadRequest(new { error = "subscriptionId is required" });
                }
                var list = await lh.ListLocationsAsync(sub, ct);
                return Results.Ok(list.Select(l => new { id = l.Id, displayName = l.DisplayName }));
            })
            .RequireAuthorization(Policies.PartnerStaff)
            .WithTags("Customers");

        var g = app.MapGroup("/customers").RequireAuthorization(Policies.PartnerStaff).WithTags("Customers");

        g.MapGet("/", async (CustomerRepository repo, CancellationToken ct) =>
        {
            // Cheap: just return the Cosmos rows. The previous implementation
            // fanned out an ARM call per customer which made this list slow
            // and unreliable (the UAMI's view of the delegation can be stale
            // or transiently 401). Delegation is now verified on-demand from
            // the Deploy page via /customers/{id}/delegation-check.
            var customers = await repo.ListAsync(ct);
            return Results.Ok(customers.Select(c => new CustomerListItem(c, "unchecked")));
        });

        // Live delegation probe: tries to read the customer subscription via
        // the partner UAMI. If it succeeds, the partner has access; if it
        // 401/403s, deployment will fail and the SPA blocks the user.
        g.MapGet("/{id}/delegation-check", async (
            string id,
            [FromQuery] string tenantId,
            CustomerRepository repo,
            LighthouseService lh,
            CancellationToken ct) =>
        {
            var c = await repo.GetAsync(id, tenantId);
            if (c is null) return Results.NotFound();
            try
            {
                var name = await lh.GetSubscriptionDisplayNameAsync(c.SubscriptionId, ct);
                if (!string.IsNullOrEmpty(name))
                {
                    return Results.Ok(new { ok = true, subscriptionDisplayName = name });
                }
                return Results.Ok(new
                {
                    ok = false,
                    error = "NoAccess",
                    message = "The partner UAMI cannot read this subscription. Verify the Lighthouse delegation in the customer tenant."
                });
            }
            catch (Exception ex)
            {
                return Results.Ok(new { ok = false, error = "Exception", message = ex.Message });
            }
        });

        g.MapGet("/{id}", async (string id, [FromQuery] string tenantId, CustomerRepository repo) =>
        {
            var c = await repo.GetAsync(id, tenantId);
            return c is null ? Results.NotFound() : Results.Ok(c);
        });

        // Live region list for the customer subscription, fetched via the
        // partner UAMI. Lets the SPA render a searchable picker without
        // requiring an interactive ARM token in the customer tenant.
        g.MapGet("/{id}/locations", async (
            string id,
            [FromQuery] string tenantId,
            CustomerRepository repo,
            LighthouseService lh,
            CancellationToken ct) =>
        {
            var c = await repo.GetAsync(id, tenantId);
            if (c is null) return Results.NotFound();
            var list = await lh.ListLocationsAsync(c.SubscriptionId, ct);
            return Results.Ok(list.Select(l => new { id = l.Id, displayName = l.DisplayName }));
        });

        g.MapDelete("/{id}", async (
            string id,
            [FromQuery] string tenantId,
            CustomerRepository repo,
            CancellationToken ct) =>
        {
            var deleted = await repo.DeleteAsync(id, tenantId, ct);
            return deleted ? Results.NoContent() : Results.NotFound();
        });

        g.MapGet("/lookup/{subscriptionId}", async (
            string subscriptionId,
            CustomerRepository repo,
            LighthouseService lh,
            CancellationToken ct) =>
        {
            // Used by the onboarding form: surface duplicates and prefill the
            // display name from the subscription itself (only works after the
            // delegation is in place — falls back to null otherwise).
            var existing = await repo.FindBySubscriptionAsync(subscriptionId, ct);
            string? subName = null;
            try { subName = await lh.GetSubscriptionDisplayNameAsync(subscriptionId, ct); }
            catch { /* ignore — partner may not have access yet */ }
            return Results.Ok(new
            {
                subscriptionDisplayName = subName,
                existingCustomer = existing is null ? null : new { existing.Id, existing.DisplayName, existing.TenantId }
            });
        });

        g.MapGet("/lookup-tenant/{tenantId}", async (
            string tenantId,
            LighthouseService lh,
            CancellationToken ct) =>
        {
            // Best-effort tenant name lookup via Microsoft Graph. Used to
            // prefill the onboarding display name as <tenant>/<subscription>.
            // Returns nulls if the partner UAMI lacks
            // CrossTenantInformation.ReadBasic.All — the SPA falls back to
            // the subscription name alone in that case.
            string? name = null;
            string? domain = null;
            try
            {
                var info = await lh.GetTenantInfoAsync(tenantId, ct);
                name = info.DisplayName;
                domain = info.DefaultDomainName;
            }
            catch { /* ignore */ }
            return Results.Ok(new { tenantDisplayName = name, defaultDomainName = domain });
        });

        g.MapPost("/", async (
            [FromBody] CreateCustomerRequest req,
            CustomerRepository repo,
            LighthouseService lh,
            ILoggerFactory lf,
            CancellationToken ct) =>
        {
            // Block double-onboarding of the same subscription. Two rows for
            // the same subscription would race on Cosmos partition keys and
            // confuse the deployment list / Lighthouse status check.
            var dup = await repo.FindBySubscriptionAsync(req.SubscriptionId);
            if (dup is not null)
            {
                return Results.Conflict(new
                {
                    error = "CustomerAlreadyOnboarded",
                    message = $"Subscription {req.SubscriptionId} is already onboarded as '{dup.DisplayName}'.",
                    customerId = dup.Id,
                    tenantId = dup.TenantId
                });
            }

            // Best-effort delegation check. Locally, DefaultAzureCredential is
            // the dev user (not the partner UAMI), so this call typically
            // can't see the customer subscription even after a successful
            // delegation. The SPA has already PUT the registration definition
            // and assignment with the customer admin's token; the worker
            // (running as the UAMI in cloud) will surface any real auth
            // issues at deploy time. Log and continue.
            try
            {
                var delegated = await lh.VerifyDelegationAsync(req.SubscriptionId);
                if (!delegated)
                {
                    lf.CreateLogger("CustomerEndpoints").LogWarning(
                        "Lighthouse delegation not visible from API for subscription {Sub}; persisting anyway.",
                        req.SubscriptionId);
                }
            }
            catch (Exception ex)
            {
                lf.CreateLogger("CustomerEndpoints").LogWarning(ex,
                    "Lighthouse verification failed for subscription {Sub}; persisting anyway.",
                    req.SubscriptionId);
            }

            // Compose displayName from <tenantName>/<subName> if the client
            // didn't pass one. Delegation is in place by now, so the partner
            // UAMI can read the customer subscription. Falls back gracefully
            // if either lookup fails (Graph perms missing, propagation lag).
            var displayName = (req.DisplayName ?? "").Trim();
            if (string.IsNullOrEmpty(displayName))
            {
                string? subName = null;
                string? tenantName = null;
                try { subName = await lh.GetSubscriptionDisplayNameAsync(req.SubscriptionId, ct); }
                catch { /* best-effort */ }
                try
                {
                    var info = await lh.GetTenantInfoAsync(req.CustomerTenantId, ct);
                    tenantName = info.DisplayName ?? info.DefaultDomainName;
                }
                catch { /* best-effort */ }
                displayName = (tenantName, subName) switch
                {
                    (string t, string s) when !string.IsNullOrWhiteSpace(t) && !string.IsNullOrWhiteSpace(s) => $"{t}/{s}",
                    (string t, _) when !string.IsNullOrWhiteSpace(t) => t,
                    (_, string s) when !string.IsNullOrWhiteSpace(s) => s,
                    _ => req.SubscriptionId
                };
            }

            var c = new Customer
            {
                TenantId = req.CustomerTenantId,
                SubscriptionId = req.SubscriptionId,
                DisplayName = displayName,
                ManagedByTenantId = req.PartnerTenantId,
                PolicyMiResourceId = req.PolicyMiResourceId ?? ""
            };
            var saved = await repo.UpsertAsync(c);
            return Results.Created($"/customers/{saved.Id}", saved);
        });

        // Edit the customer-facing display name. Other fields (subscription
        // id, tenant id, policy MI) are immutable post-onboarding; renaming
        // is the only safe in-place mutation.
        g.MapPatch("/{id}", async (
            string id,
            [FromQuery] string tenantId,
            [FromBody] UpdateCustomerRequest req,
            CustomerRepository repo,
            CancellationToken ct) =>
        {
            var c = await repo.GetAsync(id, tenantId);
            if (c is null) return Results.NotFound();
            var name = (req.DisplayName ?? "").Trim();
            if (string.IsNullOrEmpty(name))
            {
                return Results.BadRequest(new { error = "DisplayName is required" });
            }
            c.DisplayName = name;
            var saved = await repo.UpsertAsync(c, ct);
            return Results.Ok(saved);
        });
    }

    public sealed record CreateCustomerRequest(
        string SubscriptionId,
        string CustomerTenantId,
        string PartnerTenantId,
        string? DisplayName = null,
        string? PolicyMiResourceId = null);

    public sealed record UpdateCustomerRequest(string DisplayName);

    /// <summary>
    /// List item that pairs a Cosmos-stored customer with the live Lighthouse
    /// delegation status (active / revoked / unknown). "revoked" means the row
    /// is in our database but the partner can no longer reach the subscription
    /// — e.g. the customer admin removed the registrationAssignment.
    /// </summary>
    public sealed record CustomerListItem(Customer Customer, string DelegationStatus);
}
