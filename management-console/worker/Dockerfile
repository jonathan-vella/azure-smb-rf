# syntax=docker/dockerfile:1.7
# Deploy worker for the Partner Management Console.
# Runs as a Container Apps Job triggered per deployment.
# Acts as the partner UAMI; via Lighthouse delegation it can manage the
# customer subscription specified by SUBSCRIPTION_ID at runtime.

FROM mcr.microsoft.com/azure-cli:2.85.0

ARG AZD_VERSION=1.10.4

# Base image (azure-cli) is Azure Linux (Mariner) based and uses `tdnf`.
# Install OS deps + PowerShell 7 (some azd hooks invoke pwsh), then add azd.
RUN tdnf install -y git jq curl bash unzip tar ca-certificates icu gawk sed grep \
    && tdnf clean all \
    && curl -fsSL https://github.com/PowerShell/PowerShell/releases/download/v7.4.5/powershell-7.4.5-linux-x64.tar.gz \
       -o /tmp/pwsh.tar.gz \
    && mkdir -p /opt/microsoft/powershell/7 \
    && tar -xzf /tmp/pwsh.tar.gz -C /opt/microsoft/powershell/7 \
    && chmod +x /opt/microsoft/powershell/7/pwsh \
    && ln -s /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh \
    && rm /tmp/pwsh.tar.gz \
    && curl -fsSL https://aka.ms/install-azd.sh | bash -s -- --version "${AZD_VERSION}" \
    && az bicep install

WORKDIR /work
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
