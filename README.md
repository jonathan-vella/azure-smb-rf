<!-- markdownlint-disable MD013 MD033 MD041 -->

<a id="readme-top"></a>

<!-- PROJECT SHIELDS -->

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]
[![Azure][azure-shield]][azure-url]

<!-- PROJECT LOGO -->
<br />
<div align="center">
  <a href="https://github.com/jonathan-vella/azure-agentic-smb-lz">
    <img src="https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/assets/Rocket/3D/rocket_3d.png" alt="Logo" width="120" height="120">
  </a>

  <h1 align="center">Azure SMB Landing Zone</h1>

  <p align="center">
    <strong>Repeatable Azure landing zone for SMB customers.</strong>
    <br />
    On-premises migration ready • Policy-enforced • CAF-aligned
    <br />
    <br />
    <a href="#-quick-start"><strong>Quick Start »</strong></a>
    ·
    <a href="agent-output/smb-landing-zone/">View Artifacts</a>
    ·
    <a href="https://github.com/jonathan-vella/azure-agentic-smb-lz/issues/new?labels=bug">Report Bug</a>
    ·
    <a href="https://github.com/jonathan-vella/azure-agentic-smb-lz/issues/new?labels=enhancement">Request Feature</a>
  </p>
</div>

<!-- TABLE OF CONTENTS -->
<details>
  <summary>📑 Table of Contents</summary>
  <ol>
    <li><a href="#-about-the-project">About The Project</a></li>
    <li><a href="#-architecture">Architecture</a></li>
    <li><a href="#-deployment-scenarios">Deployment Scenarios</a></li>
    <li><a href="#-quick-start">Quick Start</a></li>
    <li><a href="#-included-resources">Included Resources</a></li>
    <li><a href="#-azure-policy-guardrails">Azure Policy Guardrails</a></li>
    <li><a href="#-project-structure">Project Structure</a></li>
    <li><a href="#-key-design-decisions">Key Design Decisions</a></li>
    <li><a href="#-development">Development</a></li>
    <li><a href="#-target-audience">Target Audience</a></li>
    <li><a href="#-additional-resources">Additional Resources</a></li>
    <li><a href="#-contributing">Contributing</a></li>
    <li><a href="#-license">License</a></li>
  </ol>
</details>

---

## 🚀 About The Project

Single-subscription Azure environment designed for **Microsoft Partners** hosting 1000+ small
business customers on on-premises infrastructure.

<div align="center">

| ✅ On-premises migrations |        ✅ Cost-first design         | ✅ Policy-enforced security |   ✅ Repeatable deployments   |
| :-----------------------: | :---------------------------------: | :-------------------------: | :---------------------------: |
|     Via Azure Migrate     | Resilience traded for affordability |    20 guardrail policies    | No per-customer customization |

</div>

Built with the [Agentic InfraOps](https://github.com/jonathan-vella/azure-agentic-infraops) workflow
using AI agents for requirements gathering, architecture assessment, and Bicep code generation.

### 🛠️ Built With

[![Bicep][bicep-shield]][bicep-url]
[![PowerShell][powershell-shield]][powershell-url]
[![Azure CLI][azcli-shield]][azcli-url]
[![GitHub Copilot][copilot-shield]][copilot-url]
[![Dev Containers][devcontainer-shield]][devcontainer-url]

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 🏗️ Architecture

<div align="center">
  <img src="docs/images/architecture.png" alt="SMB Landing Zone Architecture" width="800">
  <br />
  <em>Complete architecture with all optional components (Firewall, VPN Gateway)</em>
</div>

<br />

The landing zone follows a **hub-and-spoke** topology within a single subscription:

| Component             | Purpose                                                            |
| --------------------- | ------------------------------------------------------------------ |
| **Hub VNet**          | Centralized services (Bastion, Firewall, VPN Gateway, Private DNS) |
| **Spoke VNet**        | Workload hosting with NAT Gateway for outbound internet            |
| **Azure Migrate**     | Server discovery and assessment                                    |
| **Log Analytics**     | Centralized monitoring with 500 MB/day cap                         |
| **Recovery Services** | VM backup with default policy                                      |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 💰 Deployment Scenarios

Choose the scenario that fits your budget and connectivity requirements:

<div align="center">

|    Scenario    | Firewall | VPN | NAT GW | Peering | UDR | Deploy Time | Monthly Cost |
| :------------: | :------: | :-: | :----: | :-----: | :-: | :---------: | -----------: |
| **`baseline`** |    ❌    | ❌  |   ✅   |   ❌    | ❌  |   ~4 min    |     **~$48** |
| **`firewall`** |    ✅    | ❌  |   ❌   |   ✅    | ✅  |   ~15 min   |    **~$336** |
|   **`vpn`**    |    ❌    | ✅  |   ❌   |   ✅    | ❌  |   ~25 min   |    **~$187** |
|   **`full`**   |    ✅    | ✅  |   ❌   |   ✅    | ✅  |  ~40-55 min |    **~$476** |

</div>

> 💡 **Tip:** Start with `baseline` for testing, upgrade to `firewall` or `full` for production
> workloads requiring traffic inspection or hybrid connectivity.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## ⚡ Quick Start

### Prerequisites

- 🐳 Docker Desktop (or Podman, Colima, Rancher Desktop)
- 💻 VS Code with [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension
- 🤖 GitHub Copilot subscription
- ☁️ Azure subscription with Owner access

### 1️⃣ Clone and Open

```bash
git clone https://github.com/jonathan-vella/azure-agentic-smb-lz.git
cd azure-agentic-smb-lz
code .
```

### 2️⃣ Start Dev Container

Press `F1` → **Dev Containers: Reopen in Container**

> ⏱️ First build takes 3-5 minutes

### 3️⃣ Authenticate with Azure

```bash
az login
az account set --subscription "<your-subscription-id>"
```

### 4️⃣ Deploy

```powershell
cd infra/bicep/smb-landing-zone

# Preview changes (What-If)
./deploy.ps1 -Scenario baseline -WhatIf

# Deploy baseline (~$48/mo)
./deploy.ps1 -Scenario baseline

# Deploy with firewall (~$336/mo)
./deploy.ps1 -Scenario firewall

# Deploy full scenario (~$476/mo)
./deploy.ps1 -Scenario full
```

### 5️⃣ Cleanup (Optional)

When you're done testing, remove all deployed resources:

```powershell
cd infra/bicep/smb-landing-zone/scripts

# Preview what will be deleted
./Remove-SmbLandingZone.ps1 -Location swedencentral -WhatIf

# Delete all resources (no confirmation prompts)
./Remove-SmbLandingZone.ps1 -Location swedencentral -Force
```

> ⏱️ Cleanup takes 10-15 minutes (Azure Firewall and VPN Gateway take longest to delete)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 📦 Included Resources

### Always Deployed

| Resource                   | Resource Group | Configuration                |
| -------------------------- | -------------- | ---------------------------- |
| 🌐 Hub VNet                | `rg-hub`       | Pre-provisioned subnets      |
| 🌐 Spoke VNet              | `rg-spoke`     | Workload subnets + NSG       |
| 🚪 NAT Gateway             | `rg-spoke`     | Outbound internet            |
| 🔐 Azure Bastion Developer | `rg-hub`       | Secure VM access             |
| 🔗 Azure Private DNS       | `rg-hub`       | Auto-registration            |
| 📦 Azure Migrate Project   | `rg-migrate`   | Server assessment            |
| 📊 Log Analytics Workspace | `rg-monitor`   | 500 MB/day, 30-day retention |
| 💾 Recovery Services Vault | `rg-backup`    | VM backup                    |
| 💰 Cost Management Budget  | subscription   | $500/month + alerts          |
| 🛡️ Defender for Cloud      | subscription   | Free tier                    |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 🛡️ Azure Policy Guardrails

20 policies enforcing security best practices:

| Category       | Policies                                                |
| -------------- | ------------------------------------------------------- |
| **Compute**    | Allowed SKUs (B/D/E only), no public IPs, managed disks |
| **Network**    | NSG required, management ports closed, no IP forwarding |
| **Storage**    | HTTPS only, no public blob, TLS 1.2+                    |
| **Identity**   | Azure AD-only SQL, no classic resources                 |
| **Compliance** | Required tags, allowed locations, backup audit          |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 📁 Project Structure

```
├── 📁 .devcontainer/          # Dev container configuration
├── 📁 .github/
│   ├── 📁 agents/             # Copilot agents (requirements, architect, bicep-*, deploy)
│   ├── 📁 instructions/       # AI coding standards
│   ├── 📁 prompts/
│   │   └── 📄 plan-smb-landing-zone.prompt.md  # ⭐ Main prompt
│   └── 📁 templates/          # Artifact output templates
├── 📁 agent-output/
│   └── 📁 smb-landing-zone/   # Generated artifacts for this project
├── 📁 docs/
│   └── 📁 images/             # Architecture diagrams
├── 📁 infra/bicep/
│   └── 📁 smb-landing-zone/   # Bicep templates (generated by agents)
└── 📁 mcp/azure-pricing-mcp/  # Azure Pricing MCP server
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 🎯 Key Design Decisions

| Decision              | Choice                            | Rationale                    |
| --------------------- | --------------------------------- | ---------------------------- |
| **Resilience**        | Not required                      | Cost priority for SMB        |
| **SLA/RTO/RPO**       | N/A                               | Rebuild from Bicep if needed |
| **VM Access**         | Azure Bastion Developer           | No public IPs on VMs         |
| **Outbound Internet** | NAT Gateway                       | Default outbound deprecated  |
| **DNS**               | Azure Private DNS                 | Auto-registration for VMs    |
| **Regions**           | swedencentral, germanywestcentral | EU GDPR compliant            |
| **Tags**              | Environment, Owner (required)     | CAF-aligned tagging          |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 🔧 Development

### Generate Landing Zone with Agents

1. Press `Ctrl+Shift+A` → Select `@requirements`
2. Paste content from `.github/prompts/plan-smb-landing-zone.prompt.md`
3. Follow agent workflow through to deployment

### Validation Commands

```bash
# Bicep lint
bicep lint infra/bicep/smb-landing-zone/*.bicep

# Markdown lint
npm run lint:md

# Build Bicep
bicep build infra/bicep/smb-landing-zone/main.bicep
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 🎯 Target Audience

This landing zone is designed for:

- 🏢 **Microsoft Partners** hosting SMB customers on on-premises infrastructure
- 🔧 **Managed Service Providers** standardizing Azure onboarding
- 💼 **IT Consultants** delivering repeatable migration projects

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 📚 Additional Resources

| Resource                                                                               | Description                                   |
| -------------------------------------------------------------------------------------- | --------------------------------------------- |
| [Partner Quick Reference](docs/partner-quick-reference.md)                             | One-page deployment guide for partners        |
| [Agentic InfraOps Framework](https://github.com/jonathan-vella/azure-agentic-infraops) | Parent framework for AI-driven infrastructure |
| [Azure Landing Zones](https://aka.ms/alz)                                              | Microsoft reference architectures             |
| [Azure Verified Modules](https://aka.ms/avm)                                           | Bicep module registry                         |
| [Cloud Adoption Framework](https://aka.ms/caf)                                         | Naming and governance standards               |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 🤝 Contributing

Contributions are welcome! Here's how:

1. 🍴 Fork the Project
2. 🌿 Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. 💾 Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. 📤 Push to the Branch (`git push origin feature/AmazingFeature`)
5. 🔃 Open a Pull Request

Don't forget to give the project a ⭐ if you found it useful!

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 📄 License

Distributed under the MIT License. See [LICENSE](LICENSE) for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

<div align="center">
  <p>
    Made with ❤️ by <a href="https://github.com/jonathan-vella">Jonathan Vella</a>
  </p>
  <p>
    <a href="https://github.com/jonathan-vella/azure-agentic-smb-lz">
      <img src="https://img.shields.io/badge/GitHub-azure--agentic--smb--lz-blue?style=for-the-badge&logo=github" alt="GitHub Repo">
    </a>
  </p>
</div>

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->

[contributors-shield]: https://img.shields.io/github/contributors/jonathan-vella/azure-agentic-smb-lz.svg?style=for-the-badge
[contributors-url]: https://github.com/jonathan-vella/azure-agentic-smb-lz/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/jonathan-vella/azure-agentic-smb-lz.svg?style=for-the-badge
[forks-url]: https://github.com/jonathan-vella/azure-agentic-smb-lz/network/members
[stars-shield]: https://img.shields.io/github/stars/jonathan-vella/azure-agentic-smb-lz.svg?style=for-the-badge
[stars-url]: https://github.com/jonathan-vella/azure-agentic-smb-lz/stargazers
[issues-shield]: https://img.shields.io/github/issues/jonathan-vella/azure-agentic-smb-lz.svg?style=for-the-badge
[issues-url]: https://github.com/jonathan-vella/azure-agentic-smb-lz/issues
[license-shield]: https://img.shields.io/github/license/jonathan-vella/azure-agentic-smb-lz.svg?style=for-the-badge
[license-url]: https://github.com/jonathan-vella/azure-agentic-smb-lz/blob/main/LICENSE
[azure-shield]: https://img.shields.io/badge/Azure-Ready-0078D4?style=for-the-badge&logo=microsoftazure&logoColor=white
[azure-url]: https://azure.microsoft.com

<!-- TECH STACK BADGES -->

[bicep-shield]: https://img.shields.io/badge/Bicep-0.20+-00A4EF?style=for-the-badge&logo=azurefunctions&logoColor=white
[bicep-url]: https://learn.microsoft.com/azure/azure-resource-manager/bicep/
[powershell-shield]: https://img.shields.io/badge/PowerShell-7+-5391FE?style=for-the-badge&logo=powershell&logoColor=white
[powershell-url]: https://learn.microsoft.com/powershell/
[azcli-shield]: https://img.shields.io/badge/Azure_CLI-2.50+-0078D4?style=for-the-badge&logo=microsoftazure&logoColor=white
[azcli-url]: https://learn.microsoft.com/cli/azure/
[copilot-shield]: https://img.shields.io/badge/GitHub_Copilot-Enabled-000000?style=for-the-badge&logo=github&logoColor=white
[copilot-url]: https://github.com/features/copilot
[devcontainer-shield]: https://img.shields.io/badge/Dev_Containers-Ready-007ACC?style=for-the-badge&logo=docker&logoColor=white
[devcontainer-url]: https://containers.dev/
