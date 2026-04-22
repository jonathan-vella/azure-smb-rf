<!-- markdownlint-disable MD013 MD033 MD041 -->

<a id="readme-top"></a>

<!-- PROJECT SHIELDS -->

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]
[![Azure][azure-shield]][azure-url]
[![Version](https://img.shields.io/badge/version-v0.10.0-blue?style=for-the-badge)](VERSION.md)
[![Docs](https://img.shields.io/github/actions/workflow/status/jonathan-vella/azure-smb-rf/deploy-docs.yml?style=for-the-badge&label=docs)](https://jonathan-vella.github.io/azure-smb-rf/)

<!-- PROJECT LOGO -->
<br />
<div align="center">
  <a href="https://github.com/jonathan-vella/azure-smb-rf">
    <img src="https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/assets/Rocket/3D/rocket_3d.png" alt="Logo" width="120" height="120">
  </a>

  <h1 align="center">Azure SMB Ready Foundations</h1>

  <p align="center">
    <strong>A repeatable, easy-to-deploy, and well-managed Azure platform built for SMB customers.</strong>
    <br />
    Hub-spoke networking • 33 governance policies • 4 deployment scenarios • From $48/month
    <br />
    <br />
    <a href="#-quick-start"><strong>Quick Start »</strong></a>
    ·
    <a href="https://github.com/jonathan-vella/azure-smb-rf/issues/new?labels=bug">Report Bug</a>
    ·
    <a href="https://github.com/jonathan-vella/azure-smb-rf/issues/new?labels=enhancement">Request Feature</a>
  </p>
</div>

<!-- TABLE OF CONTENTS -->
<details>
  <summary>📑 Table of Contents</summary>
  <ol>
    <li><a href="#-about">About</a></li>
    <li><a href="#-deployment-scenarios">Deployment Scenarios</a></li>
    <li><a href="#-quick-start">Quick Start</a></li>
    <li><a href="#-whats-included">What's Included</a></li>
    <li><a href="#-governance">Governance</a></li>
    <li><a href="#-project-structure">Project Structure</a></li>
    <li><a href="#-documentation">Documentation</a></li>
    <li><a href="#-contributing">Contributing</a></li>
    <li><a href="#-license">License</a></li>
  </ol>
</details>

---

## 🚀 About

Azure SMB Ready Foundations deploys a complete, production-ready Azure environment using a
**hub-spoke** topology within a single subscription. Built on 13
[Azure Verified Modules](https://aka.ms/avm) and deployable with a single `azd up` command.

**Designed for** Microsoft Partners delivering repeatable Azure environments for SMB customers.

### Key Features

- **4 deployment scenarios** — baseline ($48/mo) to full ($476/mo)
- **33 MG-scoped Azure Policies** — compute, network, storage, identity, tagging, Key Vault,
  monitoring, backup
- **azd-powered** — environment-based config, pre/post-provision hooks, one-command deploy
- **13 AVM Bicep modules** — production-tested, Microsoft-maintained
- **EU GDPR regions** — swedencentral (primary), germanywestcentral (failover)

### Built With

[![Bicep][bicep-shield]][bicep-url]
[![PowerShell][powershell-shield]][powershell-url]
[![Azure CLI][azcli-shield]][azcli-url]
[![Dev Containers][devcontainer-shield]][devcontainer-url]

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 💰 Deployment Scenarios

| Scenario     | Monthly Cost | Connectivity   | Egress Control       |
| ------------ | ------------ | -------------- | -------------------- |
| **baseline** | ~$48         | Cloud-only     | NAT Gateway          |
| **firewall** | ~$336        | Cloud-only     | Azure Firewall + UDR |
| **vpn**      | ~$187        | Hybrid (IPsec) | NAT Gateway          |
| **full**     | ~$476        | Hybrid (IPsec) | Azure Firewall + UDR |

All scenarios include: hub-spoke VNets, NSGs, Bastion Developer, Key Vault (with PE),
Log Analytics, Automation Account, Recovery Vault, Azure Migrate, Budget, Defender (free CSPM),
and 33 MG-scoped governance policies.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## ⚡ Quick Start

### Prerequisites

- Azure subscription with Owner role
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) 2.60+
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) 1.9+
- [PowerShell](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) 7.4+

### Deploy in 5 Steps

```bash
# 1. Clone and navigate
git clone https://github.com/jonathan-vella/azure-smb-rf.git
cd azure-smb-rf/infra/bicep/smb-ready-foundation

# 2. Create management group (one-time)
az account management-group create --name smb-rf --display-name "SMB Ready Foundations"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
az account management-group subscription add --name smb-rf --subscription $SUBSCRIPTION_ID

# 3. Configure environment
azd env new my-foundation
azd env set SCENARIO baseline
azd env set OWNER "your@email.com"
azd env set AZURE_LOCATION swedencentral
azd env set ENVIRONMENT prod
azd env set HUB_VNET_ADDRESS_SPACE "10.0.0.0/23"
azd env set SPOKE_VNET_ADDRESS_SPACE "10.0.2.0/23"
azd env set LOG_ANALYTICS_DAILY_CAP_GB "0.5"
azd env set MANAGEMENT_GROUP_ID smb-rf

# 4. Deploy
azd up

# 5. Verify
az group list --query "[?starts_with(name,'rg-')].{name:name,state:properties.provisioningState}" -o table
```

The pre-provision hook automatically validates CIDRs, creates the MG, deploys 33 policies,
and cleans up stale resources.

> **Cleanup**: `pwsh scripts/Remove-SmbReadyFoundation.ps1 -Force -RemoveManagementGroup`

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 📦 What's Included

### Resources (6 Resource Groups)

| Resource Group        | Resources                                                        |
| --------------------- | ---------------------------------------------------------------- |
| `rg-hub-smb-{r}`      | Hub VNet, NSG, Private DNS, Firewall*, VPN GW*, Route Tables\\\* |
| `rg-spoke-prod-{r}`   | Spoke VNet, NSG, NAT Gateway\*                                   |
| `rg-monitor-smb-{r}`  | Log Analytics (500MB/day cap), Automation Account                |
| `rg-backup-smb-{r}`   | Recovery Services Vault                                          |
| `rg-security-smb-{r}` | Key Vault + Private Endpoint                                     |
| `rg-migrate-smb-{r}`  | Azure Migrate Project                                            |

\*Conditional — depends on scenario. `{r}` = region abbreviation (e.g., `swc`).

### Subscription-Scoped

- Monthly budget ($500 default) with alert at 80%/100%
- Defender for Cloud (free CSPM)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 🛡️ Governance

**33 Azure Policy assignments** at the `smb-rf` management group scope:

| Category   | Deny  | Audit  | Total  |
| ---------- | ----- | ------ | ------ |
| Compute    | 2     | 4      | 6      |
| Network    | 1     | 4      | 5      |
| Storage    | 3     | 2      | 5      |
| Identity   | 0     | 4      | 4      |
| Key Vault  | 0     | 7      | 7      |
| Tagging    | 2     | 0      | 2      |
| Monitoring | 0     | 1      | 1      |
| Backup     | 0     | 2      | 2      |
| Governance | 1     | 0      | 1      |
| **Total**  | **9** | **24** | **33** |

Management group hierarchy:

```text
Tenant Root Group
└── smb-rf (33 policy assignments)
    └── your-subscription (6 RGs + budget + Defender)
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 📁 Project Structure

```text
infra/bicep/smb-ready-foundation/
├── azure.yaml                      # azd project manifest
├── main.bicep                      # Main orchestration template (11 params)
├── main.parameters.json            # azd parameter bridge (${ENV_VAR} substitution)
├── deploy-mg.bicep                 # Management group creation template
├── hooks/
│   ├── pre-provision.ps1           # CIDR validation, MG + 33 policies, cleanup
│   └── post-provision.ps1          # Deployment summary
├── modules/
│   ├── policy-assignments-mg.bicep # 33 MG-scoped policy assignments
│   ├── networking-hub.bicep        # Hub VNet + NSG
│   ├── networking-spoke.bicep      # Spoke VNet + NSG + NAT GW
│   ├── firewall.bicep              # Azure Firewall + Policy + PIPs
│   ├── vpn-gateway.bicep           # VPN Gateway + PIP
│   ├── route-tables.bicep          # UDR for Firewall scenarios
│   ├── keyvault.bicep              # Key Vault + Private Endpoint
│   ├── monitoring.bicep            # Log Analytics Workspace
│   ├── automation.bicep            # Automation Account
│   ├── backup.bicep                # Recovery Services Vault
│   ├── migrate.bicep               # Azure Migrate Project
│   └── defender.bicep              # Defender for Cloud (free tier)
└── scripts/
    └── Remove-SmbReadyFoundation.ps1  # Full cleanup script
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 📚 Documentation

Full documentation is available in the [docs site](site/src/content/docs/):

| Section                                                                  | Content                           |
| ------------------------------------------------------------------------ | --------------------------------- |
| [Quick Start](site/src/content/docs/getting-started/quick-start.mdx)     | First deployment in 5 commands    |
| [Scenarios & Costs](site/src/content/docs/deploying/scenarios.mdx)       | 4 scenarios with cost comparison  |
| [Configuration](site/src/content/docs/deploying/configuration.mdx)       | All 11 parameters, CIDR planning  |
| [Management Group](site/src/content/docs/deploying/management-group.mdx) | MG setup, 33 policies             |
| [Customization](site/src/content/docs/operating/customization.mdx)       | Adding modules, regions, policies |
| [Teardown](site/src/content/docs/operating/teardown.mdx)                 | Cleanup and removal               |
| [Troubleshooting](site/src/content/docs/operating/troubleshooting.mdx)   | Common errors and fixes           |
| [Policy Catalog](site/src/content/docs/reference/policies.mdx)           | Complete 33-policy reference      |
| [Cost Comparison](site/src/content/docs/reference/costs.mdx)             | Detailed cost breakdown           |

Build the docs locally:

```bash
cd site && npm install && npm run build
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 🤝 Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

```bash
# Validate before committing
npm run validate:all
bicep build infra/bicep/smb-ready-foundation/main.bicep
npm run lint:md
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 📄 License

Distributed under the MIT License. See [LICENSE](LICENSE) for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

<div align="center">
  <p>Made with ❤️ by <a href="https://github.com/jonathan-vella">Jonathan Vella</a></p>
</div>

<!-- MARKDOWN LINKS & IMAGES -->

[contributors-shield]: https://img.shields.io/github/contributors/jonathan-vella/azure-smb-rf.svg?style=for-the-badge
[contributors-url]: https://github.com/jonathan-vella/azure-smb-rf/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/jonathan-vella/azure-smb-rf.svg?style=for-the-badge
[forks-url]: https://github.com/jonathan-vella/azure-smb-rf/network/members
[stars-shield]: https://img.shields.io/github/stars/jonathan-vella/azure-smb-rf.svg?style=for-the-badge
[stars-url]: https://github.com/jonathan-vella/azure-smb-rf/stargazers
[issues-shield]: https://img.shields.io/github/issues/jonathan-vella/azure-smb-rf.svg?style=for-the-badge
[issues-url]: https://github.com/jonathan-vella/azure-smb-rf/issues
[license-shield]: https://img.shields.io/github/license/jonathan-vella/azure-smb-rf.svg?style=for-the-badge
[license-url]: https://github.com/jonathan-vella/azure-smb-rf/blob/main/LICENSE
[azure-shield]: https://img.shields.io/badge/Azure-Ready-0078D4?style=for-the-badge&logo=microsoftazure&logoColor=white
[azure-url]: https://azure.microsoft.com
[bicep-shield]: https://img.shields.io/badge/Bicep-0.30+-00A4EF?style=for-the-badge&logo=azurefunctions&logoColor=white
[bicep-url]: https://learn.microsoft.com/azure/azure-resource-manager/bicep/
[powershell-shield]: https://img.shields.io/badge/PowerShell-7.4+-5391FE?style=for-the-badge&logo=powershell&logoColor=white
[powershell-url]: https://learn.microsoft.com/powershell/
[azcli-shield]: https://img.shields.io/badge/Azure_CLI-2.60+-0078D4?style=for-the-badge&logo=microsoftazure&logoColor=white
[azcli-url]: https://learn.microsoft.com/cli/azure/
[devcontainer-shield]: https://img.shields.io/badge/Dev_Containers-Ready-007ACC?style=for-the-badge&logo=docker&logoColor=white
[devcontainer-url]: https://containers.dev/
