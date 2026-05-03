using ManagementConsole.Api.Auth;
using ManagementConsole.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace ManagementConsole.Api.Endpoints;

public static class LighthouseEndpoints
{
    public static void MapLighthouseEndpoints(this IEndpointRouteBuilder app)
    {
        var g = app.MapGroup("/lighthouse").RequireAuthorization(Policies.PartnerStaff).WithTags("Lighthouse");

        g.MapGet("/template", async (LighthouseService svc, IConfiguration cfg) =>
        {
            var partnerPrincipalIds = (cfg["Lighthouse:PartnerPrincipalIds"] ?? "")
                .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            return Results.Ok(await svc.RenderDelegationTemplateAsync(partnerPrincipalIds));
        });

        g.MapGet("/payload", async (LighthouseService svc, IConfiguration cfg) =>
        {
            var partnerPrincipalIds = (cfg["Lighthouse:PartnerPrincipalIds"] ?? "")
                .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            return Results.Ok(await svc.RenderDelegationPayloadAsync(partnerPrincipalIds));
        });

        g.MapGet("/verify", async ([FromQuery] string subscriptionId, LighthouseService svc) =>
        {
            var ok = await svc.VerifyDelegationAsync(subscriptionId);
            return Results.Ok(new { delegated = ok });
        });
    }
}

public static class ScenarioEndpoints
{
    public static void MapScenarioEndpoints(this IEndpointRouteBuilder app)
    {
        // Mirror docs/partner-quick-reference.md so SPA always shows authoritative numbers.
        app.MapGet("/scenarios", () => Results.Ok(new[]
        {
            new { name = "baseline", monthlyUsd = 48,  natGateway = true,  firewall = false, vpnGateway = false, peering = false },
            new { name = "firewall", monthlyUsd = 336, natGateway = false, firewall = true,  vpnGateway = false, peering = true  },
            new { name = "vpn",      monthlyUsd = 187, natGateway = true,  firewall = false, vpnGateway = true,  peering = true  },
            new { name = "full",     monthlyUsd = 476, natGateway = false, firewall = true,  vpnGateway = true,  peering = true  }
        })).WithTags("Scenarios").RequireAuthorization(Policies.PartnerStaff);
    }
}
