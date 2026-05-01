using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Azure.Cosmos;

namespace ManagementConsole.Api.Services;

/// <summary>
/// Cosmos serializer backed by System.Text.Json. Differs from the built-in
/// <see cref="CosmosSerializationOptions"/> in one critical way: it leaves
/// dictionary keys alone. The built-in CamelCase policy mangles every key
/// (e.g. <c>OWNER</c> → <c>oWNER</c>, <c>HUB_VNET_ADDRESS_SPACE</c> →
/// <c>huB_VNET_ADDRESS_SPACE</c>), which silently broke deployment parameter
/// lockdown because callers reading prior deployments could never find the
/// expected keys.
/// </summary>
public sealed class SystemTextJsonCosmosSerializer : CosmosSerializer
{
    private readonly JsonSerializerOptions _options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        // DictionaryKeyPolicy intentionally left null so OWNER stays OWNER.
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter() },
    };

    public override T FromStream<T>(Stream stream)
    {
        using (stream)
        {
            if (typeof(Stream).IsAssignableFrom(typeof(T)))
            {
                return (T)(object)stream;
            }
            return JsonSerializer.Deserialize<T>(stream, _options)!;
        }
    }

    public override Stream ToStream<T>(T input)
    {
        var ms = new MemoryStream();
        JsonSerializer.Serialize(ms, input, _options);
        ms.Position = 0;
        return ms;
    }
}
