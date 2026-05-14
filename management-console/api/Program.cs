using ManagementConsole.Api.Auth;
using ManagementConsole.Api.Endpoints;
using ManagementConsole.Api.Services;
using Azure.Monitor.OpenTelemetry.AspNetCore;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Http.Json;
using Microsoft.Identity.Web;
using System.Text.Json.Serialization;


var builder = WebApplication.CreateBuilder(args);

// SPA sends enums as strings ("Bicep", "baseline"). Without this, model binding
// fails with 400 because System.Text.Json defaults to numeric enums.
builder.Services.Configure<JsonOptions>(o =>
{
    o.SerializerOptions.Converters.Add(new JsonStringEnumConverter(
        namingPolicy: null, allowIntegerValues: true));
    o.SerializerOptions.PropertyNameCaseInsensitive = true;
});

// AuthN / AuthZ
builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddMicrosoftIdentityWebApi(builder.Configuration.GetSection("AzureAd"));

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy(Policies.PartnerStaff, p => p
        .RequireAuthenticatedUser()
        .RequireRole(Policies.ManagementRole));

    // Belt-and-braces: any endpoint that omits an explicit policy still
    // requires the management role. Health check uses AllowAnonymous below.
    options.FallbackPolicy = options.GetPolicy(Policies.PartnerStaff);
});

// CORS is only needed for local dev (Vite on :5173 -> API on :8080). In
// production the SPA is served by nginx and proxies /api and /hubs to the
// API on the same origin, so no CORS headers are required.
if (builder.Environment.IsDevelopment())
{
    var spaOrigin = builder.Configuration["Spa:Origin"] ?? "http://localhost:5173";
    builder.Services.AddCors(o => o.AddDefaultPolicy(p =>
        p.WithOrigins(spaOrigin).AllowAnyHeader().AllowAnyMethod().AllowCredentials()));
}

// App services
builder.Services.AddSingleton<CosmosFactory>();
builder.Services.AddSingleton<CustomerRepository>();
builder.Services.AddSingleton<DeploymentRepository>();
builder.Services.AddSingleton<SettingsRepository>();
builder.Services.AddSingleton<LighthouseService>();
builder.Services.AddSingleton<DeploymentJobLauncher>();
builder.Services.AddSingleton<DeploymentLogStore>();
builder.Services.AddSingleton<VpnService>();
builder.Services.AddHttpClient("arm");

// Prerequisites template (fetched from GitHub release; see appsettings).
builder.Services.Configure<PrerequisitesOptions>(
    builder.Configuration.GetSection(PrerequisitesOptions.SectionName));
builder.Services.AddHttpClient("github");
builder.Services.AddSingleton<PrerequisitesTemplateService>();

// Surface the exception message and type to the SPA so the user sees something
// more actionable than "500 An error occurred while processing your request.".
// This is internal partner-staff tooling — exposing exception details is an
// acceptable trade-off for faster diagnosis.
builder.Services.AddProblemDetails(options =>
{
    options.CustomizeProblemDetails = ctx =>
    {
        var ex = ctx.HttpContext.Features
            .Get<Microsoft.AspNetCore.Diagnostics.IExceptionHandlerFeature>()?.Error;
        if (ex is not null)
        {
            ctx.ProblemDetails.Title = ex.GetType().Name;
            ctx.ProblemDetails.Detail = ex.Message;
            // Include inner exception message if present — ARM/KV errors often
            // wrap the useful text in InnerException.
            if (ex.InnerException is { } inner)
            {
                ctx.ProblemDetails.Extensions["innerError"] = inner.Message;
            }
        }
        ctx.ProblemDetails.Extensions["traceId"] = ctx.HttpContext.TraceIdentifier;
    };
});
builder.Services.AddHealthChecks();

// Telemetry (App Insights via OpenTelemetry; no-op if connection string unset)
if (!string.IsNullOrWhiteSpace(builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]))
{
    builder.Services.AddOpenTelemetry().UseAzureMonitor();
}

var app = builder.Build();

// Without this, unhandled exceptions return a 500 with an empty body and the
// SPA can only show the status code. AddProblemDetails() above wires up the
// JSON serializer; UseExceptionHandler() then returns a ProblemDetails body
// (status, title, detail) for any unhandled exception.
app.UseExceptionHandler();
app.UseStatusCodePages();

if (app.Environment.IsDevelopment())
{
    app.UseCors();
}
app.UseAuthentication();
app.UseAuthorization();

app.MapHealthChecks("/healthz").AllowAnonymous();
app.MapCustomerEndpoints();
app.MapDeploymentEndpoints();
app.MapLighthouseEndpoints();
app.MapScenarioEndpoints();
app.MapPrerequisitesEndpoints();
app.MapSettingsEndpoints();
app.MapVpnEndpoints();

app.Run();

public partial class Program { }
