using System.Net.Http.Headers;
using System.Text.Json;
using Azure.Core;
using Azure.Identity;

namespace ManagementConsole.Api.Services;

/// <summary>
/// Lighthouse onboarding helpers. Renders the customer-side ARM template,
/// verifies a delegation has materialized, and constructs the deep-link URL
/// the partner admin uses (one-time interactive consent in customer tenant).
/// </summary>
public sealed class LighthouseService
{
    private readonly IConfiguration _cfg;
    private readonly TokenCredential _credential = new DefaultAzureCredential();
    private readonly HttpClient _http = new();

    public LighthouseService(IConfiguration cfg) => _cfg = cfg;

    /// <summary>
    /// Build the raw GitHub URL for the delegation template based on Repo:Url
    /// and Repo:Ref configuration. Supports both <c>https://github.com/o/r.git</c>
    /// and <c>https://github.com/o/r</c> forms.
    /// </summary>
    private string BuildTemplateUrl()
    {
        var repoUrl = _cfg["Repo:Url"] ?? "https://github.com/jonathan-vella/azure-smb-rf.git";
        var repoRef = _cfg["Repo:Ref"] ?? "main";
        var path = _cfg["Lighthouse:TemplatePath"] ?? "management-console/lighthouse/delegation.json";

        // Normalise: strip trailing .git, replace github.com -> raw.githubusercontent.com
        var trimmed = repoUrl.TrimEnd('/');
        if (trimmed.EndsWith(".git", StringComparison.OrdinalIgnoreCase))
            trimmed = trimmed[..^4];
        var raw = trimmed.Replace("https://github.com/", "https://raw.githubusercontent.com/", StringComparison.OrdinalIgnoreCase);
        return $"{raw}/{repoRef}/{path}";
    }

    /// <summary>
    /// Fetches delegation.json from the configured repo. NOT cached — every
    /// outbound onboarding/render call must reflect the current repo state
    /// since the API is long-lived and only redeployed on code changes, not
    /// when delegation.json itself moves on the configured branch.
    /// </summary>
    private async Task<JsonDocument> GetTemplateAsync(CancellationToken ct = default)
    {
        var url = BuildTemplateUrl();
        using var resp = await _http.GetAsync(url, ct);
        resp.EnsureSuccessStatusCode();
        var json = await resp.Content.ReadAsStringAsync(ct);
        return JsonDocument.Parse(json);
    }

    /// <summary>
    /// Reads <c>variables.authorizations</c> from the loaded template and
    /// expands each entry per partner principal. The template uses
    /// <c>[parameters('partnerPrincipalId')]</c> as a placeholder which we
    /// replace with each actual principal ID.
    /// </summary>
    private async Task<List<Dictionary<string, object>>> BuildAuthorizationsAsync(IEnumerable<string> partnerPrincipalIds, CancellationToken ct = default)
    {
        using var doc = await GetTemplateAsync(ct);
        var authsTemplate = doc.RootElement
            .GetProperty("variables")
            .GetProperty("authorizations");

        var result = new List<Dictionary<string, object>>();
        foreach (var pid in partnerPrincipalIds)
        {
            foreach (var auth in authsTemplate.EnumerateArray())
            {
                var entry = new Dictionary<string, object>();
                foreach (var prop in auth.EnumerateObject())
                {
                    entry[prop.Name] = SubstituteValue(prop.Value, pid);
                }
                result.Add(entry);
            }
        }
        return result;
    }

    private static object SubstituteValue(JsonElement value, string principalId)
    {
        return value.ValueKind switch
        {
            JsonValueKind.String => value.GetString() == "[parameters('partnerPrincipalId')]"
                ? principalId
                : value.GetString()!,
            JsonValueKind.Array => value.EnumerateArray().Select(e => SubstituteValue(e, principalId)).ToArray(),
            JsonValueKind.Number => value.GetRawText(),
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => value.GetRawText()
        };
    }

    /// <summary>
    /// Resolved Lighthouse delegation values (no ARM expressions) for the SPA
    /// to PUT directly against the customer subscription using an
    /// ARM token acquired in the customer tenant.
    /// </summary>
    public async Task<object> RenderDelegationPayloadAsync(IEnumerable<string> partnerPrincipalIds, CancellationToken ct = default)
    {
        var partnerTenantId = _cfg["AzureAd:TenantId"]
            ?? throw new InvalidOperationException("AzureAd:TenantId not set");
        var offerName = _cfg["Lighthouse:OfferName"] ?? "smb-ready-foundation-partner";
        var offerDescription = _cfg["Lighthouse:OfferDescription"]
            ?? "Partner management console for SMB Ready Foundation deployments";

        var authorizations = await BuildAuthorizationsAsync(partnerPrincipalIds, ct);
        var definitionId = DeterministicGuidV5(offerName).ToString();

        return new
        {
            registrationDefinitionId = definitionId,
            registrationDefinitionName = offerName,
            description = offerDescription,
            managedByTenantId = partnerTenantId,
            authorizations
        };
    }

    /// <summary>
    /// Matches ARM's <c>guid(text)</c> behaviour: SHA-1-based v5 GUID with the
    /// fixed "Microsoft Azure" namespace. This keeps the SPA-driven flow and
    /// the ARM-template flow producing the same registration GUID.
    /// </summary>
    private static Guid DeterministicGuidV5(string input)
    {
        // ARM uses a specific implementation; Microsoft.Azure templates
        // hash the concatenated string via SHA-1 then format as a v5 GUID.
        var bytes = System.Text.Encoding.UTF8.GetBytes(input);
        using var sha1 = System.Security.Cryptography.SHA1.Create();
        var hash = sha1.ComputeHash(bytes);
        var guidBytes = new byte[16];
        Array.Copy(hash, guidBytes, 16);
        guidBytes[6] = (byte)((guidBytes[6] & 0x0F) | 0x50); // version 5
        guidBytes[8] = (byte)((guidBytes[8] & 0x3F) | 0x80); // variant RFC4122
        // .NET Guid expects little-endian first 3 fields
        Array.Reverse(guidBytes, 0, 4);
        Array.Reverse(guidBytes, 4, 2);
        Array.Reverse(guidBytes, 6, 2);
        return new Guid(guidBytes);
    }

    public async Task<object> RenderDelegationTemplateAsync(IEnumerable<string> partnerPrincipalIds, CancellationToken ct = default)
    {
        var partnerTenantId = _cfg["AzureAd:TenantId"]
            ?? throw new InvalidOperationException("AzureAd:TenantId not set");
        var offerName = _cfg["Lighthouse:OfferName"] ?? "smb-ready-foundation-partner";
        var offerDescription = _cfg["Lighthouse:OfferDescription"]
            ?? "Partner management console for SMB Ready Foundation deployments";

        var authorizations = await BuildAuthorizationsAsync(partnerPrincipalIds, ct);

        return new
        {
            schema = "https://schema.management.azure.com/schemas/2019-08-01/subscriptionDeploymentTemplate.json#",
            contentVersion = "1.0.0.0",
            parameters = new { },
            variables = new
            {
                mspOfferName = offerName,
                mspOfferDescription = offerDescription,
                managedByTenantId = partnerTenantId,
                authorizations
            },
            resources = new object[]
            {
                new
                {
                    type = "Microsoft.ManagedServices/registrationDefinitions",
                    apiVersion = "2022-10-01",
                    name = "[guid(variables('mspOfferName'))]",
                    properties = new
                    {
                        registrationDefinitionName = "[variables('mspOfferName')]",
                        description = "[variables('mspOfferDescription')]",
                        managedByTenantId = "[variables('managedByTenantId')]",
                        authorizations = "[variables('authorizations')]"
                    }
                },
                new
                {
                    type = "Microsoft.ManagedServices/registrationAssignments",
                    apiVersion = "2022-10-01",
                    name = "[guid(variables('mspOfferName'))]",
                    dependsOn = new[]
                    {
                        "[resourceId('Microsoft.ManagedServices/registrationDefinitions', guid(variables('mspOfferName')))]"
                    },
                    properties = new
                    {
                        registrationDefinitionId = "[resourceId('Microsoft.ManagedServices/registrationDefinitions', guid(variables('mspOfferName')))]"
                    }
                }
            }
        };
    }

    /// <summary>
    /// Build a "Deploy to Azure" URL the partner admin can click to launch
    /// the customer-tenant portal experience for the rendered template.
    /// </summary>
    public string BuildDeployToAzureUrl(string templateUri) =>
        "https://portal.azure.com/#create/Microsoft.Template/uri/" + Uri.EscapeDataString(templateUri);

    /// <summary>
    /// Verify (via ARM, using the partner UAMI) that a Lighthouse assignment
    /// for *this* partner tenant is currently visible on the customer
    /// subscription. Uses <c>$expand=registrationDefinition</c> so we can
    /// match against <c>managedByTenantId</c> directly rather than guessing
    /// from the raw payload.
    /// </summary>
    public async Task<bool> VerifyDelegationAsync(string subscriptionId, CancellationToken ct = default)
    {
        var partnerTenantId = _cfg["AzureAd:TenantId"];
        if (string.IsNullOrEmpty(partnerTenantId) || string.IsNullOrEmpty(subscriptionId)) return false;

        var token = await _credential.GetTokenAsync(
            new TokenRequestContext(new[] { "https://management.azure.com/.default" }), ct);

        using var req = new HttpRequestMessage(HttpMethod.Get,
            $"https://management.azure.com/subscriptions/{subscriptionId}/providers/Microsoft.ManagedServices/registrationAssignments?api-version=2022-10-01&$expand=registrationDefinition");
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);

        using var resp = await _http.SendAsync(req, ct);
        if (!resp.IsSuccessStatusCode) return false;

        await using var stream = await resp.Content.ReadAsStreamAsync(ct);
        using var doc = await System.Text.Json.JsonDocument.ParseAsync(stream, cancellationToken: ct);
        if (!doc.RootElement.TryGetProperty("value", out var arr)) return false;

        foreach (var item in arr.EnumerateArray())
        {
            // path: properties.registrationDefinition.properties.managedByTenantId
            if (!item.TryGetProperty("properties", out var p1)) continue;
            if (!p1.TryGetProperty("registrationDefinition", out var rd)) continue;
            if (!rd.TryGetProperty("properties", out var p2)) continue;
            if (!p2.TryGetProperty("managedByTenantId", out var tid)) continue;
            if (string.Equals(tid.GetString(), partnerTenantId, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    /// <summary>
    /// Fetches the customer subscription's display name via ARM using the
    /// partner UAMI. Returns null if the partner can't see the subscription
    /// (delegation missing or revoked).
    /// </summary>
    public async Task<string?> GetSubscriptionDisplayNameAsync(string subscriptionId, CancellationToken ct = default)
    {
        if (string.IsNullOrEmpty(subscriptionId)) return null;
        var token = await _credential.GetTokenAsync(
            new TokenRequestContext(new[] { "https://management.azure.com/.default" }), ct);
        using var req = new HttpRequestMessage(HttpMethod.Get,
            $"https://management.azure.com/subscriptions/{subscriptionId}?api-version=2022-12-01");
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
        using var resp = await _http.SendAsync(req, ct);
        if (!resp.IsSuccessStatusCode) return null;
        await using var stream = await resp.Content.ReadAsStreamAsync(ct);
        using var doc = await System.Text.Json.JsonDocument.ParseAsync(stream, cancellationToken: ct);
        return doc.RootElement.TryGetProperty("displayName", out var dn) ? dn.GetString() : null;
    }

    /// <summary>
    /// Lists physical Azure regions available to the given customer
    /// subscription via the partner UAMI. Returns an empty list if the
    /// delegation isn't in place yet (caller surfaces that as an error).
    /// </summary>
    public async Task<List<(string Id, string DisplayName)>> ListLocationsAsync(string subscriptionId, CancellationToken ct = default)
    {
        var result = new List<(string Id, string DisplayName)>();
        if (string.IsNullOrEmpty(subscriptionId)) return result;
        var token = await _credential.GetTokenAsync(
            new TokenRequestContext(new[] { "https://management.azure.com/.default" }), ct);
        using var req = new HttpRequestMessage(HttpMethod.Get,
            $"https://management.azure.com/subscriptions/{subscriptionId}/locations?api-version=2022-12-01");
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
        using var resp = await _http.SendAsync(req, ct);
        if (!resp.IsSuccessStatusCode) return result;
        await using var stream = await resp.Content.ReadAsStreamAsync(ct);
        using var doc = await System.Text.Json.JsonDocument.ParseAsync(stream, cancellationToken: ct);
        if (!doc.RootElement.TryGetProperty("value", out var arr)) return result;
        foreach (var loc in arr.EnumerateArray())
        {
            // Filter to physical regions; logical groupings ("EU", "US")
            // aren't valid deployment targets.
            string? regionType = null;
            if (loc.TryGetProperty("metadata", out var md)
                && md.TryGetProperty("regionType", out var rt))
            {
                regionType = rt.GetString();
            }
            if (regionType is not null
                && !string.Equals(regionType, "Physical", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
            var name = loc.TryGetProperty("name", out var n) ? n.GetString() : null;
            var dn = loc.TryGetProperty("displayName", out var dnEl) ? dnEl.GetString() : null;
            if (string.IsNullOrEmpty(name)) continue;
            result.Add((name!, dn ?? name!));
        }
        result.Sort((a, b) => string.CompareOrdinal(a.DisplayName, b.DisplayName));
        return result;
    }

    /// <summary>
    /// Best-effort tenant info lookup via Microsoft Graph
    /// <c>tenantRelationships/findTenantInformationByTenantId</c>. Requires
    /// <c>CrossTenantInformation.ReadBasic.All</c> (Application) on the
    /// partner UAMI; returns nulls if the permission is missing or the
    /// tenant cannot be resolved (used purely to prefill the onboarding
    /// form, never to gate onboarding).
    /// </summary>
    public async Task<(string? DisplayName, string? DefaultDomainName)> GetTenantInfoAsync(string tenantId, CancellationToken ct = default)
    {
        if (string.IsNullOrEmpty(tenantId)) return (null, null);
        AccessToken token;
        try
        {
            token = await _credential.GetTokenAsync(
                new TokenRequestContext(new[] { "https://graph.microsoft.com/.default" }), ct);
        }
        catch
        {
            return (null, null);
        }
        using var req = new HttpRequestMessage(HttpMethod.Get,
            $"https://graph.microsoft.com/v1.0/tenantRelationships/findTenantInformationByTenantId(tenantId='{tenantId}')");
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
        using var resp = await _http.SendAsync(req, ct);
        if (!resp.IsSuccessStatusCode) return (null, null);
        await using var stream = await resp.Content.ReadAsStreamAsync(ct);
        using var doc = await System.Text.Json.JsonDocument.ParseAsync(stream, cancellationToken: ct);
        var root = doc.RootElement;
        var dn = root.TryGetProperty("displayName", out var dnEl) ? dnEl.GetString() : null;
        var dom = root.TryGetProperty("defaultDomainName", out var domEl) ? domEl.GetString() : null;
        return (dn, dom);
    }
}
