using ManagementConsole.Api.Auth;
using ManagementConsole.Api.Models;
using ManagementConsole.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace ManagementConsole.Api.Endpoints;

public static class VpnEndpoints
{
    public static void MapVpnEndpoints(this IEndpointRouteBuilder app)
    {
        var g = app.MapGroup("/vpn").RequireAuthorization(Policies.PartnerStaff).WithTags("Vpn");

        // GET /vpn/{customerId}/{envName}?tenantId=...
        // Returns the live VPN status for the customer's foundation: gateway
        // public IP, current LNG values, whether the placeholders are still
        // in place, whether a PSK exists, and the connection state if any.
        g.MapGet("/{customerId}/{envName}", async (
            string customerId,
            string envName,
            [FromQuery] string tenantId,
            CustomerRepository customers,
            DeploymentRepository deployments,
            VpnService vpn) =>
        {
            var (err, ctx) = await ResolveContextAsync(customerId, tenantId, envName, customers, deployments);
            if (err is not null) return err;
            var status = await vpn.GetStatusAsync(ctx!.SubscriptionId, envName, ctx.Location, customerId);
            return Results.Ok(status);
        });

        // POST /vpn/{customerId}/{envName}/psk?tenantId=...
        // Generates a new PSK and stores it in the partner Key Vault. The
        // plaintext is returned ONCE in the response; subsequent reads only
        // get the metadata. If the user closes the modal without copying
        // they must rotate again.
        g.MapPost("/{customerId}/{envName}/psk", async (
            string customerId,
            string envName,
            [FromQuery] string tenantId,
            CustomerRepository customers,
            DeploymentRepository deployments,
            VpnService vpn) =>
        {
            var (err, _) = await ResolveContextAsync(customerId, tenantId, envName, customers, deployments);
            if (err is not null) return err;
            var psk = await vpn.RotatePskAsync(customerId, envName);
            return Results.Ok(new { psk, rotatedAt = DateTime.UtcNow });
        });

        // POST /vpn/{customerId}/{envName}/connect?tenantId=...
        // Updates the LNG with the partner-supplied peer IP / CIDRs and
        // creates or updates the IPsec connection. If RotatePsk=true (or no
        // PSK exists yet) a fresh PSK is generated and the plaintext is
        // returned ONCE in the response so the partner can copy it to their
        // on-prem device.
        g.MapPost("/{customerId}/{envName}/connect", async (
            string customerId,
            string envName,
            [FromQuery] string tenantId,
            [FromBody] ConnectVpnRequest req,
            CustomerRepository customers,
            DeploymentRepository deployments,
            VpnService vpn) =>
        {
            var (err, ctx) = await ResolveContextAsync(customerId, tenantId, envName, customers, deployments);
            if (err is not null) return err;
            try
            {
                var result = await vpn.ConnectAsync(
                    ctx!.SubscriptionId, envName, ctx.Location, customerId,
                    new VpnService.ConnectRequest(
                        OnPremGatewayIp: req.OnPremGatewayIp,
                        OnPremCidrs: req.OnPremCidrs,
                        Ipsec: req.Ipsec,
                        RotatePsk: req.RotatePsk));
                return Results.Accepted($"/vpn/{customerId}/{envName}", result);
            }
            catch (ArgumentException ex)
            {
                return Results.BadRequest(new { error = "InvalidRequest", message = ex.Message });
            }
        });

        // DELETE /vpn/{customerId}/{envName}/connection?tenantId=...
        // Tears down the IPsec connection but leaves the LNG/PSK intact so
        // re-connecting is one click away. Returns 204 even if the
        // connection didn't exist (idempotent).
        g.MapDelete("/{customerId}/{envName}/connection", async (
            string customerId,
            string envName,
            [FromQuery] string tenantId,
            CustomerRepository customers,
            DeploymentRepository deployments,
            VpnService vpn) =>
        {
            var (err, ctx) = await ResolveContextAsync(customerId, tenantId, envName, customers, deployments);
            if (err is not null) return err;
            await vpn.DeleteConnectionAsync(ctx!.SubscriptionId, envName, ctx.Location);
            return Results.NoContent();
        });
    }

    private sealed record VpnContext(string SubscriptionId, string Location, Scenario LastScenario);

    /// <summary>
    /// Resolves the customer, validates that the most recent successful
    /// deployment for <paramref name="envName"/> used a VPN-bearing scenario
    /// (Vpn or Full) and pulls the LOCATION param off it. The location is
    /// the foundation's deployment location, which is what we need to derive
    /// resource-group + resource names that the foundation produced.
    /// </summary>
    private static async Task<(IResult? error, VpnContext? ctx)> ResolveContextAsync(
        string customerId, string tenantId, string envName,
        CustomerRepository customers, DeploymentRepository deployments)
    {
        var customer = await customers.GetAsync(customerId, tenantId);
        if (customer is null) return (Results.NotFound(new { error = "CustomerNotFound" }), null);

        var history = await deployments.ListByCustomerAsync(customerId);
        var lastSucceeded = history
            .Where(d => string.Equals(d.EnvironmentName, envName, StringComparison.Ordinal)
                        && d.Status == DeploymentStatus.Succeeded)
            .OrderByDescending(d => d.CompletedAt ?? d.CreatedAt)
            .FirstOrDefault();
        if (lastSucceeded is null)
        {
            return (Results.BadRequest(new
            {
                error = "NoSuccessfulDeployment",
                message = $"No successful deployment found for environment '{envName}'.",
            }), null);
        }
        if (lastSucceeded.Scenario is not (Scenario.Vpn or Scenario.Full))
        {
            return (Results.BadRequest(new
            {
                error = "ScenarioWithoutVpn",
                message = $"Last deployment scenario was '{lastSucceeded.Scenario}'. VPN configuration requires the 'vpn' or 'full' scenario.",
            }), null);
        }

        if (lastSucceeded.Parameters is null
            || !lastSucceeded.Parameters.TryGetValue("LOCATION", out var location)
            || string.IsNullOrWhiteSpace(location))
        {
            return (Results.BadRequest(new
            {
                error = "MissingLocation",
                message = "The deployment record has no LOCATION parameter; cannot derive foundation resource names.",
            }), null);
        }

        return (null, new VpnContext(customer.SubscriptionId, location, lastSucceeded.Scenario));
    }
}

/// <summary>
/// Body payload for POST /vpn/{customerId}/{envName}/connect.
/// </summary>
public sealed record ConnectVpnRequest(
    string OnPremGatewayIp,
    IReadOnlyList<string> OnPremCidrs,
    IpsecPolicyDto? Ipsec,
    bool RotatePsk);
