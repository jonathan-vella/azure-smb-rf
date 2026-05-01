using ManagementConsole.Api.Auth;
using ManagementConsole.Api.Models;
using ManagementConsole.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace ManagementConsole.Api.Endpoints;

public static class DeploymentEndpoints
{
    public static void MapDeploymentEndpoints(this IEndpointRouteBuilder app)
    {
        var g = app.MapGroup("/deployments").RequireAuthorization(Policies.PartnerStaff).WithTags("Deployments");

        g.MapGet("/{customerId}", async (string customerId, DeploymentRepository repo) =>
            Results.Ok(await repo.ListByCustomerAsync(customerId)));

        g.MapGet("/{customerId}/{id}", async (string customerId, string id, DeploymentRepository repo) =>
        {
            var d = await repo.GetAsync(id, customerId);
            return d is null ? Results.NotFound() : Results.Ok(d);
        });

        g.MapPost("/", async (
            [FromBody] CreateDeploymentRequest req,
            CustomerRepository customers,
            DeploymentRepository deployments,
            DeploymentJobLauncher launcher,
            ILogger<Program> log,
            HttpContext http) =>
        {
            var customer = await customers.GetAsync(req.CustomerId, req.CustomerTenantId);
            if (customer is null) return Results.NotFound();

            // Foundation main.bicep restricts `environment` to dev/staging/prod;
            // reject anything else here so we fail fast before the worker runs.
            if (req.EnvironmentName is not ("dev" or "staging" or "prod"))
            {
                return Results.BadRequest(new
                {
                    error = "InvalidEnvironmentName",
                    message = "EnvironmentName must be one of: dev, staging, prod.",
                });
            }

            if (await deployments.HasInFlightAsync(req.CustomerId, req.EnvironmentName))
            {
                return Results.Conflict(new
                {
                    error = "DeploymentInFlight",
                    message = "Another deployment is already running for this environment."
                });
            }

            // Enforce the same lockdown the SPA shows: once an environment has
            // a successful deployment its network ranges and scenario floor
            // are fixed. SPA validation is for UX; this is for safety.
            var history = await deployments.ListByCustomerAsync(req.CustomerId);
            var lastSucceeded = history
                .Where(d => string.Equals(d.EnvironmentName, req.EnvironmentName, StringComparison.Ordinal)
                            && d.Status == DeploymentStatus.Succeeded)
                .OrderByDescending(d => d.CompletedAt ?? d.CreatedAt)
                .FirstOrDefault();
            if (lastSucceeded is not null)
            {
                static bool ScenarioAllowed(Scenario prev, Scenario next) => prev switch
                {
                    Scenario.Baseline => true,
                    Scenario.Firewall => next is Scenario.Firewall or Scenario.Full,
                    Scenario.Vpn => next is Scenario.Vpn or Scenario.Full,
                    Scenario.Full => next == Scenario.Full,
                    _ => true,
                };
                if (!ScenarioAllowed(lastSucceeded.Scenario, req.Scenario))
                {
                    return Results.BadRequest(new
                    {
                        error = "ScenarioRegression",
                        message = $"Cannot transition from '{lastSucceeded.Scenario}' to '{req.Scenario}' for environment '{req.EnvironmentName}'.",
                    });
                }
                static string? Get(Dictionary<string, string>? d, string k)
                    => d != null && d.TryGetValue(k, out var v) ? v : null;
                var prevHub = Get(lastSucceeded.Parameters, "HUB_VNET_ADDRESS_SPACE");
                var prevSpoke = Get(lastSucceeded.Parameters, "SPOKE_VNET_ADDRESS_SPACE");
                var prevOnPrem = Get(lastSucceeded.Parameters, "ON_PREMISES_ADDRESS_SPACE");
                var newHub = Get(req.Parameters, "HUB_VNET_ADDRESS_SPACE");
                var newSpoke = Get(req.Parameters, "SPOKE_VNET_ADDRESS_SPACE");
                var newOnPrem = Get(req.Parameters, "ON_PREMISES_ADDRESS_SPACE");
                if (prevHub is not null && newHub is not null && prevHub != newHub)
                {
                    return Results.BadRequest(new
                    {
                        error = "NetworkRangeLocked",
                        message = $"HUB_VNET_ADDRESS_SPACE is locked to '{prevHub}' for this environment.",
                    });
                }
                if (prevSpoke is not null && newSpoke is not null && prevSpoke != newSpoke)
                {
                    return Results.BadRequest(new
                    {
                        error = "NetworkRangeLocked",
                        message = $"SPOKE_VNET_ADDRESS_SPACE is locked to '{prevSpoke}' for this environment.",
                    });
                }
                if (!string.IsNullOrEmpty(prevOnPrem) && !string.IsNullOrEmpty(newOnPrem) && prevOnPrem != newOnPrem)
                {
                    return Results.BadRequest(new
                    {
                        error = "NetworkRangeLocked",
                        message = $"ON_PREMISES_ADDRESS_SPACE is locked to '{prevOnPrem}' for this environment.",
                    });
                }
            }

            // VPN/Full scenarios require an on-premises CIDR for the local
            // network gateway / route propagation. Reject up-front so the
            // worker doesn't burn a 5-minute deploy just to fail validation.
            if (req.Scenario is Scenario.Vpn or Scenario.Full)
            {
                var onPrem = req.Parameters != null
                    && req.Parameters.TryGetValue("ON_PREMISES_ADDRESS_SPACE", out var v)
                    ? v
                    : null;
                if (string.IsNullOrWhiteSpace(onPrem))
                {
                    return Results.BadRequest(new
                    {
                        error = "OnPremisesAddressSpaceRequired",
                        message = $"Scenario '{req.Scenario}' requires ON_PREMISES_ADDRESS_SPACE (e.g. '192.168.0.0/16').",
                    });
                }
            }

            var d = new Deployment
            {
                CustomerId = req.CustomerId,
                EnvironmentName = req.EnvironmentName,
                Scenario = req.Scenario,
                Parameters = req.Parameters ?? new(),
                CreatedBy = http.User.Identity?.Name ?? "unknown"
            };
            var saved = await deployments.CreateAsync(d);
            // Cosmos's CamelCase serializer mangles dictionary keys on round-trip
            // (OWNER -> owner, HUB_VNET_ADDRESS_SPACE -> huB_VNET_ADDRESS_SPACE),
            // which breaks azd parameter binding in the worker. Restore the
            // original casing from the request before launching the job.
            saved.Parameters = d.Parameters;

            // Launching the Container Apps Job can fail (RBAC, missing job,
            // ARM throttling). Surface the real reason to the SPA *and* mark
            // the just-created deployment as failed so it doesn't sit in
            // 'Pending' forever blocking future deploys via HasInFlightAsync.
            try
            {
                saved.JobExecutionName = await launcher.LaunchAsync(saved, customer);
                saved.Status = DeploymentStatus.Running;
                saved.StartedAt = DateTimeOffset.UtcNow;
                await deployments.UpdateAsync(saved);
            }
            catch (Exception ex)
            {
                log.LogError(ex, "Failed to launch worker job for deployment {Deployment}", saved.Id);
                saved.Status = DeploymentStatus.Failed;
                saved.FailureReason = ex.Message;
                saved.CompletedAt = DateTimeOffset.UtcNow;
                try { await deployments.UpdateAsync(saved); } catch { /* best-effort */ }
                return Results.Problem(
                    title: "Failed to launch deployment job",
                    detail: ex.Message,
                    statusCode: StatusCodes.Status502BadGateway);
            }

            return Results.Accepted($"/deployments/{saved.CustomerId}/{saved.Id}", saved);
        });

        // Worker callback: status updates from the running Container Apps Job.
        // Auth uses the same UAMI bearer token the worker carries.
        g.MapPost("/{customerId}/{id}/status", async (
            string customerId, string id,
            [FromBody] StatusUpdate update,
            DeploymentRepository repo) =>
        {
            var d = await repo.GetAsync(id, customerId);
            if (d is null) return Results.NotFound();
            d.Status = update.Status;
            d.FailureReason = update.FailureReason;
            if (update.Status is DeploymentStatus.Succeeded or DeploymentStatus.Failed or DeploymentStatus.Cancelled)
                d.CompletedAt = DateTimeOffset.UtcNow;
            await repo.UpdateAsync(d);
            return Results.NoContent();
        }).RequireAuthorization(Policies.PartnerStaff);

        // Worker callback: appends stdout/stderr lines from the job to a
        // per-deployment append blob. The SPA polls the cursor-based GET
        // endpoint below to render a live console — no SignalR / WS needed.
        g.MapPost("/{customerId}/{id}/logs", async (
            string customerId, string id,
            [FromBody] LogBatch batch,
            DeploymentLogStore store) =>
        {
            if (batch.Lines is null || batch.Lines.Length == 0) return Results.NoContent();
            await store.AppendAsync(customerId, id, batch.Lines);
            return Results.NoContent();
        }).RequireAuthorization(Policies.PartnerStaff);

        // Cursor-based log replay for the SPA. The client passes ?fromLine=N
        // (the count of lines it has already rendered) and we return only
        // the new tail plus the new line count so the next poll can advance
        // the cursor. The blob is canonical and append-only so this is
        // monotonic and safe across replicas / refreshes.
        g.MapGet("/{customerId}/{id}/logs", async (
            string customerId, string id, int? fromLine,
            DeploymentLogStore store) =>
        {
            var text = await store.ReadAsync(customerId, id) ?? string.Empty;
            var all = text.Length == 0
                ? Array.Empty<string>()
                : text.TrimEnd('\n').Split('\n');
            var from = fromLine.GetValueOrDefault(0);
            if (from < 0) from = 0;
            if (from > all.Length) from = all.Length;
            var slice = from == 0 ? all : all[from..];
            return Results.Ok(new { lines = slice, nextLine = all.Length });
        });

        // Stop a running deployment. Best-effort: signals the Container Apps
        // Job execution to stop and immediately marks the deployment Cancelled
        // so the UI / HasInFlightAsync gate unblocks even if the worker takes
        // a moment to actually exit.
        g.MapPost("/{customerId}/{id}/cancel", async (
            string customerId, string id,
            DeploymentRepository repo,
            DeploymentJobLauncher launcher,
            ILogger<Program> log) =>
        {
            var d = await repo.GetAsync(id, customerId);
            if (d is null) return Results.NotFound();
            if (d.Status is not (DeploymentStatus.Queued or DeploymentStatus.Running))
            {
                return Results.Conflict(new
                {
                    error = "NotCancellable",
                    message = $"Deployment is {d.Status} and cannot be cancelled."
                });
            }

            var stopped = false;
            if (!string.IsNullOrEmpty(d.JobExecutionName))
            {
                try { stopped = await launcher.StopExecutionAsync(d.JobExecutionName); }
                catch (Exception ex)
                {
                    log.LogWarning(ex, "Stop request failed for execution {Execution}", d.JobExecutionName);
                }
            }

            d.Status = DeploymentStatus.Cancelled;
            d.FailureReason = stopped ? "Cancelled by user." : "Cancelled by user (execution not found or already gone).";
            d.CompletedAt = DateTimeOffset.UtcNow;
            await repo.UpdateAsync(d);
            return Results.Ok(d);
        });
    }

    public sealed record CreateDeploymentRequest(
        string CustomerId,
        string CustomerTenantId,
        string EnvironmentName,
        Scenario Scenario,
        Dictionary<string, string>? Parameters);

    public sealed record StatusUpdate(DeploymentStatus Status, string? FailureReason);

    public sealed record LogBatch(string[] Lines);
}
