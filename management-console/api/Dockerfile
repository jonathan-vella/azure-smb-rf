# syntax=docker/dockerfile:1.7
FROM mcr.microsoft.com/dotnet/sdk:10.0-azurelinux3.0 AS build
WORKDIR /src
COPY ManagementConsole.Api.csproj ./
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app /p:UseAppHost=false

# Fetch the official Bicep CLI single-file binary. Bicep is a self-contained
# NativeAOT executable, so it runs in distroless runtimes that have the
# expected glibc / icu / openssl native libraries (azurelinux3 ships them).
FROM mcr.microsoft.com/azurelinux/base/core:3.0 AS bicep
ARG BICEP_VERSION=latest
RUN tdnf install -y ca-certificates curl tar && tdnf clean all
RUN set -eux; \
    if [ "$BICEP_VERSION" = "latest" ]; then \
        URL="https://github.com/Azure/bicep/releases/latest/download/bicep-linux-x64"; \
    else \
        URL="https://github.com/Azure/bicep/releases/download/${BICEP_VERSION}/bicep-linux-x64"; \
    fi; \
    curl -fsSL -o /usr/local/bin/bicep "$URL"; \
    chmod +x /usr/local/bin/bicep; \
    /usr/local/bin/bicep --version

# Distroless runtime: smaller image, non-root by default, no shell or package
# manager. Listens on :8080 out of the box (ASPNETCORE_HTTP_PORTS=8080).
FROM mcr.microsoft.com/dotnet/aspnet:10.0-azurelinux3.0-distroless AS runtime
WORKDIR /app
COPY --from=build /app .
COPY --from=bicep /usr/local/bin/bicep /usr/local/bin/bicep
ENV PATH="/usr/local/bin:${PATH}"
EXPOSE 8080
ENTRYPOINT ["dotnet", "ManagementConsole.Api.dll"]
