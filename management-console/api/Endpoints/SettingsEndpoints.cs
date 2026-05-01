using ManagementConsole.Api.Auth;
using ManagementConsole.Api.Models;
using ManagementConsole.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace ManagementConsole.Api.Endpoints;

/// <summary>
/// Partner-wide application settings. Currently exposes the source repo
/// (URL + ref) used both for foundation template lookups and the worker's
/// deployment clone.
/// </summary>
public static class SettingsEndpoints
{
    public static void MapSettingsEndpoints(this IEndpointRouteBuilder app)
    {
        var g = app.MapGroup("/settings")
            .RequireAuthorization(Policies.PartnerStaff)
            .WithTags("Settings");

        g.MapGet("/", async (SettingsRepository repo, CancellationToken ct) =>
        {
            var s = await repo.GetAsync(ct);
            return Results.Ok(s);
        });

        g.MapPut("/", async (
            [FromBody] UpdateSettingsRequest body,
            SettingsRepository repo,
            CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(body.RepoUrl) || string.IsNullOrWhiteSpace(body.RepoRef))
            {
                return Results.BadRequest(new { error = "RepoUrl and RepoRef are required" });
            }
            var current = await repo.GetAsync(ct);
            current.RepoUrl = body.RepoUrl.Trim();
            current.RepoRef = body.RepoRef.Trim();
            try
            {
                var saved = await repo.UpsertAsync(current, ct);
                return Results.Ok(saved);
            }
            catch (InvalidOperationException ex)
            {
                // SettingsRepository wraps Cosmos 404 (missing container) in
                // an InvalidOperationException with an actionable message.
                return Results.Problem(
                    title: "Settings store not provisioned",
                    detail: ex.Message,
                    statusCode: StatusCodes.Status503ServiceUnavailable);
            }
        });
    }

    public sealed record UpdateSettingsRequest(string RepoUrl, string RepoRef);
}
