using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Azure.Core;
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;

namespace ManagementConsole.Api.Services;

/// <summary>
/// Drives the post-deploy VPN connection wiring for the smb-ready-foundation
/// VPN/Full scenarios. The foundation deploys the VPN Gateway and a
/// placeholder Local Network Gateway (LNG) with RFC 5737 documentation
/// addresses; this service lets the partner:
/// <list type="bullet">
///   <item>Generate &amp; store an IPsec pre-shared key in the partner KV.</item>
///   <item>Update the LNG's gatewayIpAddress + addressPrefixes with real
///         on-prem values supplied by the partner.</item>
///   <item>Create or update the IPsec Connection between the VPN Gateway
///         and the LNG using the stored PSK and a customizable IPsec policy.</item>
/// </list>
/// All ARM ops target the customer subscription via Lighthouse-delegated
/// Contributor on the partner UAMI; KV ops target the partner KV (the same
/// one the API container already binds to via KEY_VAULT_URI).
/// </summary>
public sealed class VpnService
{
    // Foundation regionAbbreviations table (main.bicep). Must stay in sync
    // because the API has to derive the same resource names the foundation
    // produced; if the foundation grows a region, mirror it here.
    private static readonly Dictionary<string, string> RegionAbbreviations = new(StringComparer.OrdinalIgnoreCase)
    {
        ["swedencentral"] = "swc",
        ["germanywestcentral"] = "gwc",
    };

    // Microsoft.Network management API version used for all ARM calls below.
    private const string NetworkApiVersion = "2024-05-01";

    private readonly TokenCredential _credential;
    private readonly HttpClient _http;
    private readonly IConfiguration _cfg;
    private readonly ILogger<VpnService> _log;

    public VpnService(IHttpClientFactory httpFactory, IConfiguration cfg, ILogger<VpnService> log)
    {
        _credential = new DefaultAzureCredential();
        _http = httpFactory.CreateClient("arm");
        _cfg = cfg;
        _log = log;
    }

    // ------------------------------------------------------------------ //
    // Naming derivation
    // ------------------------------------------------------------------ //

    public sealed record VpnNames(
        string HubResourceGroup,
        string GatewayName,
        string LocalNetworkGatewayName,
        string PublicIpName,
        string ConnectionName,
        string RegionShort,
        // Tags inherited from the VPN gateway. Required so PUTs on the
        // connection / LNG satisfy management-group policy that demands
        // Environment + Owner tags on every resource.
        Dictionary<string, string> InheritedTags);

    /// <summary>
    /// Resolves the actual foundation-deployed resource names by listing the
    /// hub resource group. The foundation builds names from its own
    /// `environment` parameter (e.g. `smb`, `prod`), which is independent of
    /// the management-console deployment env, so hardcoding `{envName}` in
    /// the name pattern is unsafe. Instead we trust the hub-RG convention
    /// (rg-hub-smb-{regionShort}) and discover the single VPN GW + LNG that
    /// live there. The connection name is derived from the LNG name to keep
    /// upserts idempotent across calls.
    /// </summary>
    public async Task<VpnNames> ResolveNamesAsync(string subscriptionId, string location, CancellationToken ct = default)
    {
        if (!RegionAbbreviations.TryGetValue(location, out var regionShort))
        {
            throw new InvalidOperationException(
                $"Unknown region '{location}'. Update RegionAbbreviations to match foundation main.bicep.");
        }
        var hubRg = $"rg-hub-smb-{regionShort}";

        var gws = await ArmListAsync(
            $"/subscriptions/{subscriptionId}/resourceGroups/{hubRg}/providers/Microsoft.Network/virtualNetworkGateways", ct)
            ?? throw new InvalidOperationException(
                $"Hub resource group '{hubRg}' not found in subscription '{subscriptionId}'. Has the VPN/Full scenario deployed successfully?");
        var gw = gws.FirstOrDefault();
        if (gw.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidOperationException(
                $"No VPN Gateway found in '{hubRg}'. Has the VPN/Full scenario deployed successfully?");
        }
        var gwName = gw.GetProperty("name").GetString() ?? "";

        // Inherit gateway tags so connection/LNG PUTs satisfy MG-level
        // 'require tag' policies (Environment, Owner) without forcing the
        // partner to re-enter values the foundation already supplied.
        var inheritedTags = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (gw.TryGetProperty("tags", out var gwTags) && gwTags.ValueKind == JsonValueKind.Object)
        {
            foreach (var p in gwTags.EnumerateObject())
            {
                if (p.Value.ValueKind == JsonValueKind.String)
                    inheritedTags[p.Name] = p.Value.GetString() ?? "";
            }
        }

        var lngs = await ArmListAsync(
            $"/subscriptions/{subscriptionId}/resourceGroups/{hubRg}/providers/Microsoft.Network/localNetworkGateways", ct)
            ?? new List<JsonElement>();
        var lng = lngs.FirstOrDefault();
        if (lng.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidOperationException(
                $"No Local Network Gateway found in '{hubRg}'. Foundation should deploy a placeholder LNG.");
        }
        var lngName = lng.GetProperty("name").GetString() ?? "";

        // Resolve the GW's public IP name from its ipConfigurations[0].
        // Format: .../publicIPAddresses/{name}; we only need the trailing name.
        var pipName = "";
        if (gw.GetProperty("properties").TryGetProperty("ipConfigurations", out var ipcfgs)
            && ipcfgs.ValueKind == JsonValueKind.Array && ipcfgs.GetArrayLength() > 0
            && ipcfgs[0].GetProperty("properties").TryGetProperty("publicIPAddress", out var pipRef)
            && pipRef.TryGetProperty("id", out var pipIdEl)
            && pipIdEl.GetString() is string pipId)
        {
            pipName = pipId.Split('/').LastOrDefault() ?? "";
        }

        // Connection name: shadow the LNG's `lng-` prefix → `conn-` so
        // repeated upserts target the same resource regardless of foundation
        // env-suffix drift.
        var connName = lngName.StartsWith("lng-", StringComparison.OrdinalIgnoreCase)
            ? "conn-" + lngName.Substring(4)
            : $"conn-{lngName}";

        return new VpnNames(hubRg, gwName, lngName, pipName, connName, regionShort, inheritedTags);
    }

    // ------------------------------------------------------------------ //
    // Status read
    // ------------------------------------------------------------------ //

    public sealed record VpnStatus(
        string GatewayPublicIp,
        string GatewayResourceId,
        string LocalNetworkGatewayName,
        string LocalNetworkGatewayResourceId,
        string CurrentOnPremGatewayIp,
        IReadOnlyList<string> CurrentOnPremCidrs,
        bool HasPlaceholderAddresses,
        bool HasPsk,
        string? ConnectionName,
        string? ConnectionResourceId,
        string? ConnectionStatus,
        IpsecPolicyDto? CurrentIpsecPolicy);

    public async Task<VpnStatus> GetStatusAsync(
        string subscriptionId, string envName, string location, string customerId,
        CancellationToken ct = default)
    {
        var names = await ResolveNamesAsync(subscriptionId, location, ct);
        var gw = await ArmGetAsync(
            $"/subscriptions/{subscriptionId}/resourceGroups/{names.HubResourceGroup}/providers/Microsoft.Network/virtualNetworkGateways/{names.GatewayName}",
            ct) ?? throw new InvalidOperationException(
                $"VPN Gateway '{names.GatewayName}' not found in '{names.HubResourceGroup}'. Has the VPN/Full scenario deployed successfully?");
        var lng = await ArmGetAsync(
            $"/subscriptions/{subscriptionId}/resourceGroups/{names.HubResourceGroup}/providers/Microsoft.Network/localNetworkGateways/{names.LocalNetworkGatewayName}",
            ct) ?? throw new InvalidOperationException(
                $"Local Network Gateway '{names.LocalNetworkGatewayName}' not found.");

        // Public IP name was discovered from the gateway's ipConfigurations[0]
        // during ResolveNamesAsync; an empty value means the GW has no
        // ipConfigurations yet (still provisioning) which is rare but possible.
        var pip = string.IsNullOrEmpty(names.PublicIpName)
            ? null
            : await ArmGetAsync(
                $"/subscriptions/{subscriptionId}/resourceGroups/{names.HubResourceGroup}/providers/Microsoft.Network/publicIPAddresses/{names.PublicIpName}",
                ct);
        var publicIp = pip?.GetProperty("properties").TryGetProperty("ipAddress", out var ipEl) == true
            ? ipEl.GetString() ?? ""
            : "";

        var lngProps = lng.GetProperty("properties");
        var currentGwIp = lngProps.TryGetProperty("gatewayIpAddress", out var gIp) ? gIp.GetString() ?? "" : "";
        var currentCidrs = new List<string>();
        if (lngProps.TryGetProperty("localNetworkAddressSpace", out var space)
            && space.TryGetProperty("addressPrefixes", out var prefixes)
            && prefixes.ValueKind == JsonValueKind.Array)
        {
            foreach (var p in prefixes.EnumerateArray())
            {
                if (p.GetString() is string s && !string.IsNullOrWhiteSpace(s)) currentCidrs.Add(s);
            }
        }
        // RFC 5737 documentation prefix is the foundation placeholder -
        // surface this so the UI can prompt for real values.
        var placeholder = currentGwIp == "192.0.2.1"
            || currentCidrs.Any(c => c.StartsWith("192.0.2.", StringComparison.Ordinal));

        // Connection lookup is best-effort; a 404 means "no tunnel yet"
        // which is the expected initial state, not an error.
        JsonElement? conn = await ArmGetAsync(
            $"/subscriptions/{subscriptionId}/resourceGroups/{names.HubResourceGroup}/providers/Microsoft.Network/connections/{names.ConnectionName}",
            ct);
        string? connStatus = null;
        IpsecPolicyDto? ipsec = null;
        if (conn is not null)
        {
            var cp = conn.Value.GetProperty("properties");
            if (cp.TryGetProperty("connectionStatus", out var cs)) connStatus = cs.GetString();
            if (cp.TryGetProperty("ipsecPolicies", out var pol) && pol.ValueKind == JsonValueKind.Array
                && pol.GetArrayLength() > 0)
            {
                ipsec = IpsecPolicyDto.From(pol[0]);
            }
        }

        var hasPsk = await SecretExistsAsync(PskSecretName(customerId, envName), ct);

        return new VpnStatus(
            GatewayPublicIp: publicIp,
            GatewayResourceId: gw.GetProperty("id").GetString() ?? "",
            LocalNetworkGatewayName: names.LocalNetworkGatewayName,
            LocalNetworkGatewayResourceId: lng.GetProperty("id").GetString() ?? "",
            CurrentOnPremGatewayIp: currentGwIp,
            CurrentOnPremCidrs: currentCidrs,
            HasPlaceholderAddresses: placeholder,
            HasPsk: hasPsk,
            ConnectionName: conn is null ? null : names.ConnectionName,
            ConnectionResourceId: conn?.GetProperty("id").GetString(),
            ConnectionStatus: connStatus,
            CurrentIpsecPolicy: ipsec);
    }

    // ------------------------------------------------------------------ //
    // PSK rotation
    // ------------------------------------------------------------------ //

    /// <summary>
    /// Generates a fresh 32-byte random PSK, stores it in the partner KV
    /// under <c>vpn-psk-{customerId}-{envName}</c>, and returns the
    /// plaintext to the caller. Plaintext is returned ONCE; subsequent
    /// reads from the SPA only get the metadata.
    /// </summary>
    public async Task<string> RotatePskAsync(string customerId, string envName, CancellationToken ct = default)
    {
        // 32 bytes of CSPRNG entropy → base64 yields a 44-char ASCII string,
        // which is comfortably within the Azure VPN sharedKey limits and
        // typeable into vendor consoles when needed for cross-checks.
        var bytes = RandomNumberGenerator.GetBytes(32);
        var psk = Convert.ToBase64String(bytes);
        var client = SecretClient();
        var name = PskSecretName(customerId, envName);
        await client.SetSecretAsync(new KeyVaultSecret(name, psk)
        {
            Properties =
            {
                ContentType = "text/plain",
                Tags = { ["customerId"] = customerId, ["envName"] = envName, ["purpose"] = "vpn-psk" },
            },
        }, ct);
        _log.LogInformation("Rotated VPN PSK for {Customer}/{Env}", customerId, envName);
        return psk;
    }

    // ------------------------------------------------------------------ //
    // Connect (LNG update + connection upsert)
    // ------------------------------------------------------------------ //

    public sealed record ConnectRequest(
        string OnPremGatewayIp,
        IReadOnlyList<string> OnPremCidrs,
        IpsecPolicyDto? Ipsec,
        bool RotatePsk);

    public sealed record ConnectResult(string ConnectionResourceId, string ConnectionName, bool PskRotated, string? PlaintextPskOnce);

    public async Task<ConnectResult> ConnectAsync(
        string subscriptionId, string envName, string location, string customerId,
        ConnectRequest req, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(req.OnPremGatewayIp))
            throw new ArgumentException("OnPremGatewayIp is required.", nameof(req));
        if (req.OnPremCidrs == null || req.OnPremCidrs.Count == 0)
            throw new ArgumentException("At least one on-prem CIDR is required.", nameof(req));

        var names = await ResolveNamesAsync(subscriptionId, location, ct);

        // Step 1: PUT the LNG with the partner-supplied peer IP / prefixes.
        // PUT (not PATCH) on Microsoft.Network/localNetworkGateways replaces
        // the resource, but since we read+merge nothing else lives on the
        // LNG that we'd lose (no BGP, no tags we care about).
        var lngUrl =
            $"/subscriptions/{subscriptionId}/resourceGroups/{names.HubResourceGroup}/providers/Microsoft.Network/localNetworkGateways/{names.LocalNetworkGatewayName}";
        // Read first to preserve location & tags - PUT semantics replace the
        // entire resource so omitting these would clear them.
        var existingLng = await ArmGetAsync(lngUrl, ct)
            ?? throw new InvalidOperationException($"LNG '{names.LocalNetworkGatewayName}' not found.");
        var lngLocation = existingLng.GetProperty("location").GetString();
        JsonElement? existingTags = existingLng.TryGetProperty("tags", out var tEl) ? tEl : (JsonElement?)null;

        var lngBody = new Dictionary<string, object?>
        {
            ["location"] = lngLocation,
            ["properties"] = new Dictionary<string, object?>
            {
                ["gatewayIpAddress"] = req.OnPremGatewayIp,
                ["localNetworkAddressSpace"] = new Dictionary<string, object?>
                {
                    ["addressPrefixes"] = req.OnPremCidrs.ToArray(),
                },
            },
        };
        // Merge LNG's existing tags with gateway-inherited tags so policy
        // required tags (Environment, Owner) are guaranteed even if a prior
        // hand-edit stripped them from the LNG.
        var mergedLngTags = new Dictionary<string, string>(names.InheritedTags, StringComparer.OrdinalIgnoreCase);
        if (existingTags is JsonElement tagsEl && tagsEl.ValueKind == JsonValueKind.Object)
        {
            foreach (var p in tagsEl.EnumerateObject())
            {
                if (p.Value.ValueKind == JsonValueKind.String)
                    mergedLngTags[p.Name] = p.Value.GetString() ?? "";
            }
        }
        if (mergedLngTags.Count > 0) lngBody["tags"] = mergedLngTags;
        await ArmPutAsync(lngUrl, lngBody, ct);
        _log.LogInformation("Updated LNG {Lng} (peer={Peer}, prefixes={Count})",
            names.LocalNetworkGatewayName, req.OnPremGatewayIp, req.OnPremCidrs.Count);

        // Step 2: ensure a PSK exists (auto-rotate if missing or if the caller asked).
        var pskName = PskSecretName(customerId, envName);
        string psk;
        bool rotated = false;
        string? plaintextOnce = null;
        if (req.RotatePsk || !await SecretExistsAsync(pskName, ct))
        {
            psk = await RotatePskAsync(customerId, envName, ct);
            rotated = true;
            plaintextOnce = psk;
        }
        else
        {
            psk = (await SecretClient().GetSecretAsync(pskName, cancellationToken: ct)).Value.Value;
        }

        // Step 3: PUT the connection. We resolve the gateway + LNG resource
        // ids directly rather than referencing them via subResource so the
        // PUT body is self-contained and works across api-version drift.
        var gwResourceId =
            $"/subscriptions/{subscriptionId}/resourceGroups/{names.HubResourceGroup}/providers/Microsoft.Network/virtualNetworkGateways/{names.GatewayName}";
        var lngResourceId =
            $"/subscriptions/{subscriptionId}/resourceGroups/{names.HubResourceGroup}/providers/Microsoft.Network/localNetworkGateways/{names.LocalNetworkGatewayName}";

        var ipsec = req.Ipsec ?? IpsecPolicyDto.Default;
        var connProps = new Dictionary<string, object?>
        {
            ["connectionType"] = "IPsec",
            ["connectionProtocol"] = "IKEv2",
            ["enableBgp"] = false,
            ["sharedKey"] = psk,
            ["virtualNetworkGateway1"] = new Dictionary<string, object?>
            {
                ["id"] = gwResourceId,
                // ARM requires a 'properties' bag here even though it is empty;
                // omitting it produces "InvalidParameter: virtualNetworkGateway1.properties".
                ["properties"] = new Dictionary<string, object?>(),
            },
            ["localNetworkGateway2"] = new Dictionary<string, object?>
            {
                ["id"] = lngResourceId,
                ["properties"] = new Dictionary<string, object?>(),
            },
            ["ipsecPolicies"] = new[] { ipsec.ToArmObject() },
        };
        var connBody = new Dictionary<string, object?>
        {
            ["location"] = lngLocation,
            ["properties"] = connProps,
        };
        // Inherit tags from the VPN gateway so MG policies requiring
        // Environment/Owner tags do not deny the PUT (RequestDisallowedByPolicy).
        if (names.InheritedTags.Count > 0)
        {
            connBody["tags"] = new Dictionary<string, string>(names.InheritedTags);
        }
        var connUrl =
            $"/subscriptions/{subscriptionId}/resourceGroups/{names.HubResourceGroup}/providers/Microsoft.Network/connections/{names.ConnectionName}";
        var connResult = await ArmPutAsync(connUrl, connBody, ct);
        var connId = connResult.GetProperty("id").GetString() ?? "";
        _log.LogInformation("Upserted VPN Connection {Conn}", names.ConnectionName);

        return new ConnectResult(connId, names.ConnectionName, rotated, plaintextOnce);
    }

    public async Task<bool> DeleteConnectionAsync(
        string subscriptionId, string envName, string location, CancellationToken ct = default)
    {
        var names = await ResolveNamesAsync(subscriptionId, location, ct);
        var url =
            $"/subscriptions/{subscriptionId}/resourceGroups/{names.HubResourceGroup}/providers/Microsoft.Network/connections/{names.ConnectionName}";
        return await ArmDeleteAsync(url, ct);
    }

    // ------------------------------------------------------------------ //
    // Helpers
    // ------------------------------------------------------------------ //

    private static string PskSecretName(string customerId, string envName)
    {
        // KV secret names allow [0-9A-Za-z-]; customerId is a GUID, envName is
        // restricted to dev/staging/prod. Sanitise defensively in case either
        // assumption ever loosens.
        static string Sanitize(string s) => new string(s.Select(c => char.IsLetterOrDigit(c) || c == '-' ? c : '-').ToArray());
        return $"vpn-psk-{Sanitize(customerId)}-{Sanitize(envName)}";
    }

    private SecretClient SecretClient()
    {
        var uri = _cfg["KEY_VAULT_URI"]
            ?? throw new InvalidOperationException("KEY_VAULT_URI not set.");
        return new SecretClient(new Uri(uri), _credential);
    }

    private async Task<bool> SecretExistsAsync(string name, CancellationToken ct)
    {
        try
        {
            await SecretClient().GetSecretAsync(name, cancellationToken: ct);
            return true;
        }
        catch (Azure.RequestFailedException ex) when (ex.Status == 404)
        {
            return false;
        }
    }

    /// <summary>
    /// GET a list-style ARM endpoint and return the `value` array as a list
    /// of cloned JsonElements. Returns null if the parent resource group
    /// does not exist (404) so callers can produce a friendlier error.
    /// </summary>
    private async Task<List<JsonElement>?> ArmListAsync(string path, CancellationToken ct)
    {
        var url = $"https://management.azure.com{path}?api-version={NetworkApiVersion}";
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        await AuthorizeAsync(req, ct);
        using var resp = await _http.SendAsync(req, ct);
        if (resp.StatusCode == System.Net.HttpStatusCode.NotFound) return null;
        if (!resp.IsSuccessStatusCode)
        {
            var body = await resp.Content.ReadAsStringAsync(ct);
            throw new InvalidOperationException($"GET {path} returned {(int)resp.StatusCode}: {body}");
        }
        var stream = await resp.Content.ReadAsStreamAsync(ct);
        using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);
        var list = new List<JsonElement>();
        if (doc.RootElement.TryGetProperty("value", out var arr) && arr.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in arr.EnumerateArray()) list.Add(item.Clone());
        }
        return list;
    }

    private async Task<JsonElement?> ArmGetAsync(string path, CancellationToken ct)
    {
        var url = $"https://management.azure.com{path}?api-version={NetworkApiVersion}";
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        await AuthorizeAsync(req, ct);
        using var resp = await _http.SendAsync(req, ct);
        if (resp.StatusCode == System.Net.HttpStatusCode.NotFound) return null;
        if (!resp.IsSuccessStatusCode)
        {
            var body = await resp.Content.ReadAsStringAsync(ct);
            throw new InvalidOperationException($"GET {path} returned {(int)resp.StatusCode}: {body}");
        }
        var stream = await resp.Content.ReadAsStreamAsync(ct);
        using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);
        return doc.RootElement.Clone();
    }

    private async Task<JsonElement> ArmPutAsync(string path, object body, CancellationToken ct)
    {
        var url = $"https://management.azure.com{path}?api-version={NetworkApiVersion}";
        using var req = new HttpRequestMessage(HttpMethod.Put, url)
        {
            Content = new StringContent(
                JsonSerializer.Serialize(body, JsonOpts), Encoding.UTF8, "application/json"),
        };
        await AuthorizeAsync(req, ct);
        using var resp = await _http.SendAsync(req, ct);
        var text = await resp.Content.ReadAsStringAsync(ct);
        if (!resp.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"PUT {path} returned {(int)resp.StatusCode}: {text}");
        }
        // Connection PUT can return 200 (sync) or 201/200 + provisioningState=Updating
        // (async). We don't poll the LRO here because the caller's UI can
        // poll connectionStatus on its own and the ARM body already contains
        // a self-link in `id`.
        using var doc = JsonDocument.Parse(text);
        return doc.RootElement.Clone();
    }

    private async Task<bool> ArmDeleteAsync(string path, CancellationToken ct)
    {
        var url = $"https://management.azure.com{path}?api-version={NetworkApiVersion}";
        using var req = new HttpRequestMessage(HttpMethod.Delete, url);
        await AuthorizeAsync(req, ct);
        using var resp = await _http.SendAsync(req, ct);
        if (resp.StatusCode == System.Net.HttpStatusCode.NotFound) return false;
        if (!resp.IsSuccessStatusCode)
        {
            var body = await resp.Content.ReadAsStringAsync(ct);
            throw new InvalidOperationException($"DELETE {path} returned {(int)resp.StatusCode}: {body}");
        }
        return true;
    }

    private async Task AuthorizeAsync(HttpRequestMessage req, CancellationToken ct)
    {
        var token = await _credential.GetTokenAsync(
            new TokenRequestContext(new[] { "https://management.azure.com/.default" }), ct);
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
    }

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull,
    };
}

/// <summary>
/// IPsec policy values exposed to the SPA. Matches the screenshot the
/// partner showed: IKEv2 + AES-256/SHA256/DHGroup14 for Phase 1 (IKE) and
/// AES-256/SHA256/PFS14 for Phase 2 (ESP). Azure's API has a single
/// <c>saLifeTimeSeconds</c>; the UI surfaces both Phase 1 and Phase 2 SA
/// lifetimes for parity with vendor consoles, and we send the smaller of
/// the two so neither side renegotiates before the other expects to.
/// </summary>
public sealed record IpsecPolicyDto(
    string IkeEncryption,        // AES256
    string IkeIntegrity,         // SHA256
    string DhGroup,              // DHGroup14
    int IkeLifetimeSeconds,      // 28800
    string IpsecEncryption,      // AES256
    string IpsecIntegrity,       // SHA256
    string PfsGroup,             // PFS14
    int IpsecLifetimeSeconds)    // 27000
{
    public static IpsecPolicyDto Default => new(
        IkeEncryption: "AES256",
        IkeIntegrity: "SHA256",
        DhGroup: "DHGroup14",
        IkeLifetimeSeconds: 28800,
        IpsecEncryption: "AES256",
        IpsecIntegrity: "SHA256",
        PfsGroup: "PFS14",
        IpsecLifetimeSeconds: 27000);

    public static IpsecPolicyDto From(JsonElement el) => new(
        IkeEncryption: el.GetProperty("ikeEncryption").GetString() ?? "AES256",
        IkeIntegrity: el.GetProperty("ikeIntegrity").GetString() ?? "SHA256",
        DhGroup: el.GetProperty("dhGroup").GetString() ?? "DHGroup14",
        IkeLifetimeSeconds: el.TryGetProperty("saLifeTimeSeconds", out var ll) ? ll.GetInt32() : 28800,
        IpsecEncryption: el.GetProperty("ipsecEncryption").GetString() ?? "AES256",
        IpsecIntegrity: el.GetProperty("ipsecIntegrity").GetString() ?? "SHA256",
        PfsGroup: el.GetProperty("pfsGroup").GetString() ?? "PFS14",
        IpsecLifetimeSeconds: el.TryGetProperty("saDataSizeKilobytes", out _)
            && el.TryGetProperty("saLifeTimeSeconds", out var pl) ? pl.GetInt32() : 27000);

    public IDictionary<string, object?> ToArmObject() => new Dictionary<string, object?>
    {
        ["saLifeTimeSeconds"] = Math.Min(IkeLifetimeSeconds, IpsecLifetimeSeconds),
        // 102_400_000 KB (≈100 GB) is Azure's default. Not exposed to UI.
        ["saDataSizeKilobytes"] = 102_400_000,
        ["ipsecEncryption"] = IpsecEncryption,
        ["ipsecIntegrity"] = IpsecIntegrity,
        ["ikeEncryption"] = IkeEncryption,
        ["ikeIntegrity"] = IkeIntegrity,
        ["dhGroup"] = DhGroup,
        ["pfsGroup"] = PfsGroup,
    };
}
