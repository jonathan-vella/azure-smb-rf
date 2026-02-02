# Agentic InfraOps - Copilot Instructions

> **Agentic InfraOps** - Azure infrastructure engineered by agents. Verified. Well-Architected. Deployable.
>
> **Version**: 0.3.0 | **Region**: swedencentral | **License**: MIT

## Core Mission

Transform Azure infrastructure requirements into deploy-ready Bicep code using coordinated AI agents, aligned with
Azure Well-Architected Framework (WAF) and Azure Verified Modules (AVM).

## Agent Workflow (7 Steps)

Agents coordinate through artifact handoffs via `.github/agents/*.agent.md`:

1. **Requirements** (`requirements` agent) → `01-requirements.md`
2. **Architecture** (`architect` agent) → `02-architecture-assessment.md` + cost estimates via Azure Pricing MCP
3. **Design Artifacts** (`diagram`, `adr` agents) → `03-des-*.{py,png,md}` (optional)
4. **Planning** (`bicep-plan` agent) → `04-implementation-plan.md` + governance constraints
5. **Implementation** (`bicep-code` agent) → Bicep templates in `infra/bicep/{project}/`
6. **Deploy** (`deploy` agent) → `06-deployment-summary.md` + resource validation
7. **As-Built** (`diagram`, `adr`, `docs` agents) → `07-*.md` documentation suite (6 files)

**Key Rule**: Each agent saves outputs to `agent-output/{project}/` and passes context via handoff prompts.

## Deployment Scenarios

Choose scenario via `./deploy.ps1 -Scenario <name>`:

| Scenario     | Features                        | Deploy Time | Monthly Cost |
| ------------ | ------------------------------- | ----------- | ------------ |
| **baseline** | NAT Gateway only (cloud-native) | ~4 min      | ~$48         |
| **firewall** | Azure Firewall + UDR            | ~15 min     | ~$336        |
| **vpn**      | VPN Gateway + Gateway Transit   | ~25 min     | ~$187        |
| **full**     | Firewall + VPN + UDR            | ~40-55 min  | ~$476        |

> 💡 Start with `baseline` for testing; upgrade to `firewall` or `full` for production.

## Critical Defaults

Source of truth: [.github/agents/\_shared/defaults.md](agents/_shared/defaults.md)

| Setting             | Value                                          | Notes                                              |
| ------------------- | ---------------------------------------------- | -------------------------------------------------- |
| **Default Region**  | `swedencentral`                                | EU GDPR-compliant; alt: `germanywestcentral`       |
| **Required Tags**   | `Environment`, `ManagedBy`, `Project`, `Owner` | All resources must include these tags              |
| **VM Backup Tag**   | `Backup: 'true'`                               | Recommended for VMs; auto-enrolls via Azure Policy |
| **Unique Suffix**   | `uniqueString(resourceGroup().id)` in bicep    | Generate once in `main.bicep`, pass to all modules |
| **Key Vault Name**  | `kv-{short}-{env}-{suffix}` (≤24 chars)        | Always include suffix to guarantee uniqueness      |
| **Storage Account** | `st{short}{env}{suffix}` (≤24 chars, no `-`)   | Lowercase+numbers only; no hyphens                 |
| **SQL Server Auth** | Azure AD-only (`azureADOnlyAuthentication`)    | No SQL auth usernames/passwords                    |
| **Zone Redundancy** | App Service Plans: P1v4+ only                  | Not S1/P1v2; required for HA                       |

## AVM-First Policy (MANDATORY)

**All Bicep implementations MUST use Azure Verified Modules (AVM) where available.**

| Rule                    | Requirement                                                      |
| ----------------------- | ---------------------------------------------------------------- |
| **Gate Check**          | Run `mcp_bicep_list_avm_metadata` before planning any resource   |
| **AVM Registry**        | `br/public:avm/res/{service}/{resource}:{version}`               |
| **Version Freshness**   | Always fetch latest version from AVM registry                    |
| **Raw Bicep Exception** | Only if no AVM exists—document rationale + create tracking issue |
| **Documentation**       | https://aka.ms/avm                                               |

## Architecture Essentials

### Artifact Output Structure

All agent outputs go to `agent-output/{project}/` with strict naming and H2 structure:

- **01-requirements.md**: Project Overview, Functional Requirements, NFRs, Compliance, Budget, Operational, Regional
- **02-architecture-assessment.md**: Requirements Validation, Executive Summary, WAF Pillars, SKU Recs, Decisions, Handoff
- **04-implementation-plan.md**: Overview, Resource Inventory, Module Structure, Tasks, Dependencies, Naming, Security
- **04-governance-constraints.md**: Azure Policy Compliance, Required Tags, Security, Cost, Network Policies

See [validation rules](../scripts/validate-artifact-templates.mjs) for all artifacts.

### Handoff Pattern

Each agent defines `handoffs` in its agent definition linking to the next agent with context:

```yaml
handoffs:
  - label: "Create WAF Assessment"
    agent: architect
    prompt: "Assess the requirements above for WAF alignment..."
    send: true
```

Data flows through artifact files + agent context, not via copy-paste.

## Developer Workflows

### Running Agents

`Ctrl+Shift+A` → Select agent → Type prompt → Approve before execution

### Validation

```bash
# Lint Bicep templates
bicep lint infra/bicep/{project}/*.bicep

# Validate artifact structure
npm run validate

# Lint markdown
npm run lint:md
```

### Local Testing

```bash
# Set Azure subscription
az account set --subscription "<sub-id>"

# Deploy (PowerShell)
cd infra/bicep/smb-landing-zone
./deploy.ps1 -Scenario baseline -WhatIf  # Preview
./deploy.ps1 -Scenario baseline          # Deploy

# Cleanup (⚠️ deletes policies, RGs, role assignments)
cd scripts
./Remove-SmbLandingZone.ps1 -Location swedencentral -WhatIf  # Preview
./Remove-SmbLandingZone.ps1 -Location swedencentral -Force   # Delete all
```

> **⚠️ Cleanup deletes**: 20 Azure Policy assignments, 5 resource groups (`rg-hub-*`,
> `rg-spoke-*`, `rg-monitor-*`, `rg-backup-*`, `rg-migrate-*`), Cost Management budget,
> and orphaned role assignments. Takes 10-15 minutes (Firewall/VPN deletions are slow).

### MCP Integration

The Azure Pricing MCP server (`.mcp/azure-pricing-mcp/`) integrates with agents to fetch real-time SKU pricing:

- Used by `architect` agent for cost estimations in WAF assessments
- Used by `bicep-plan` agent for SKU recommendations
- Enable in VS Code settings; pre-configured in `.vscode/mcp.json`

## Key Files & Directories

| File/Dir                                  | Purpose                                                     |
| ----------------------------------------- | ----------------------------------------------------------- |
| `.github/agents/*.agent.md`               | Agent definitions with front matter (name, tools, handoffs) |
| `.github/agents/_shared/defaults.md`      | Shared config: regions, tags, naming conventions, security  |
| `.github/instructions/`                   | File-type rules (Bicep, Markdown, PowerShell, agents, etc.) |
| `.github/templates/`                      | H2 skeleton files for artifact generation                   |
| `agent-output/{project}/`                 | Project-scoped artifacts (01-07 sequentially)               |
| `infra/bicep/{project}/`                  | Bicep module library (main.bicep + modules/)                |
| `mcp/azure-pricing-mcp/`                  | Azure Pricing MCP server for cost estimation                |
| `.vscode/mcp.json`                        | MCP server configuration (pre-configured)                   |
| `scripts/validate-artifact-templates.mjs` | CI validation of artifact H2 structure                      |

## Skills

Reusable skills in `.github/skills/` provide domain-specific capabilities:

| Skill            | Purpose                                     | Trigger Keywords                                                             |
| ---------------- | ------------------------------------------- | ---------------------------------------------------------------------------- |
| `azure-diagrams` | Architecture diagrams with 700+ Azure icons | "create diagram", "visualize", "architecture diagram", "generate from Bicep" |
| `github-issues`  | Create/update GitHub issues via MCP         | "create issue", "file bug", "request feature", "update issue"                |

**Invocation**: Skills are activated when trigger keywords appear in prompts.
The `diagram.agent.md` references `azure-diagrams` skill files via `references:` front matter,
giving it access to 700+ component imports and layout patterns.

## Project Structure

```
azure-smb-landing-zone/
├── .github/
│   ├── agents/                    # 9 agents: requirements, architect, bicep-plan,
│   │                              # bicep-code, deploy, diagram, adr, docs, diagnose
│   │   ├── _shared/defaults.md    # Regions, tags, CAF naming, AVM standards
│   │   ├── requirements.agent.md  # Step 1: Gather infrastructure needs
│   │   ├── architect.agent.md     # Step 2: WAF assessment + cost estimates
│   │   ├── bicep-plan.agent.md    # Step 4: Implementation planning
│   │   ├── bicep-code.agent.md    # Step 5: Bicep code generation
│   │   ├── deploy.agent.md        # Step 6: Azure deployment
│   │   ├── diagram.agent.md       # Step 3/7: Architecture diagrams
│   │   ├── adr.agent.md           # Step 3/7: Architecture Decision Records
│   │   ├── docs.agent.md          # Step 7: Workload documentation
│   │   └── diagnose.agent.md      # Troubleshooting helper
│   ├── instructions/              # Rules for specific file types (applied via .gitattributes)
│   ├── skills/                    # Reusable skills (azure-diagrams, github-issues)
│   ├── templates/                 # H2 skeleton files for artifact generation
│   └── copilot-instructions.md    # THIS FILE
├── agent-output/{project}/        # All agent-generated artifacts (01-07)
├── infra/bicep/                   # Bicep module library
│   └── {project}/                 # Project-specific templates
│       ├── main.bicep             # Entry point (generates uniqueSuffix, orchestrates modules)
│       └── modules/               # Feature modules (networking, compute, data, etc.)
├── mcp/azure-pricing-mcp/         # Azure Pricing MCP server
├── scripts/                       # Validation and workflow automation
│   ├── validate-artifact-templates.mjs  # CI: Artifact H2 validation
│   ├── validate-cost-estimate-templates.mjs # CI: Cost estimate validation
│   └── workflow-generator/        # Mermaid → PNG/GIF animation
└── docs/                          # Repository documentation
```

## Tech Stack

| Category            | Tools                                           |
| ------------------- | ----------------------------------------------- |
| **IaC**             | Bicep (primary), Terraform (optional)           |
| **Automation**      | PowerShell 7+, Azure CLI 2.50+, Bicep CLI 0.20+ |
| **Platform**        | Azure (public cloud)                            |
| **AI**              | GitHub Copilot with custom agents               |
| **Dev Environment** | VS Code Dev Container (Ubuntu 24.04)            |

## Critical Patterns

### Unique Resource Names

```bicep
// main.bicep - Generate once, pass to ALL modules
var uniqueSuffix = uniqueString(resourceGroup().id)

module keyVault 'modules/key-vault.bicep' = {
  params: { uniqueSuffix: uniqueSuffix }
}

// modules/key-vault.bicep
param uniqueSuffix string
var kvName = 'kv-${take(projectName, 8)}-${environment}-${take(uniqueSuffix, 6)}'
```

### Required Tags on All Resources

```bicep
tags: {
  Environment: 'dev'      // dev, staging, prod
  ManagedBy: 'Bicep'      // or 'Terraform'
  Project: projectName
  Owner: owner
  Backup: 'true'          // Recommended for VMs - triggers auto-enrollment
}
```

### VM Backup Auto-Enrollment

VMs tagged with `Backup: true` are automatically enrolled via Azure Policy (`smb-lz-backup-02`):

- **Schedule**: Daily @ 02:00 UTC
- **Retention**: 30 days daily, 12 weeks weekly, 12 months monthly
- **Policy Effect**: DeployIfNotExists (auto-configures backup)

### Security Defaults

| Setting                    | Value                             |
| -------------------------- | --------------------------------- |
| `supportsHttpsTrafficOnly` | `true`                            |
| `minimumTlsVersion`        | `'TLS1_2'`                        |
| `allowBlobPublicAccess`    | `false`                           |
| Managed Identities         | Preferred over connection strings |

### Azure Policy Compliance

| Policy                    | Solution                          |
| ------------------------- | --------------------------------- |
| SQL Azure AD-only auth    | `azureADOnlyAuthentication: true` |
| Zone redundancy           | Use P1v4+ SKU (not Standard)      |
| Storage shared key access | Use identity-based connections    |

## Validation Commands

```bash
# Bicep
bicep build infra/bicep/{project}/main.bicep
bicep lint infra/bicep/{project}/main.bicep

# Markdown
npm run lint:md
```

## Agent-Specific Guidance

### Requirements Agent

- Captures comprehensive infrastructure needs via `01-requirements.md`
- Hands off to Architect for WAF assessment
- Uses `@plan` context for initial requirements gathering

### Architect Agent

- Creates WAF assessments aligned with Azure Well-Architected Framework
- Integrates Azure Pricing MCP for real-time cost estimates
- Generates `02-architecture-assessment.md` with SKU recommendations
- Hands off to Bicep Plan or Design Artifacts agents

### Bicep Plan Agent

- Discovers Azure Policy governance constraints (tag requirements, resource types allowed, etc.)
- Creates detailed implementation plans in `04-implementation-plan.md`
- Produces `04-governance-constraints.md` for compliance
- Hands off to Bicep Code agent for implementation

### Bicep Code Agent

- Generates Bicep modules in `infra/bicep/{project}/`
- Follows Azure Verified Modules (AVM) standards
- Ensures unique resource names via suffix pattern
- Produces `05-implementation-reference.md` with validation status
- Hands off to Deploy agent

### Deploy Agent

- Executes `bicep build` and `what-if` analysis before deployment
- Manages Azure authentication and subscription selection
- Generates `06-deployment-summary.md` with deployed resource details
- Validates post-deployment resources

### Diagram Agent

- Generates Python architecture diagrams using `diagrams` library
- Creates `03-des-diagram.py` (design) and `07-ab-diagram.py` (as-built)
- Produces PNG files for visual documentation

### ADR Agent

- Documents architecture decisions as formal ADRs
- Creates `03-des-adr-*.md` (design) and `07-ab-adr-*.md` (as-built)
- Includes WAF trade-offs and decision rationale

### Docs Agent

- Generates comprehensive workload documentation
- Creates 6 Step 7 documents:
  - `07-design-document.md` - Complete technical design
  - `07-operations-runbook.md` - Day-2 operations procedures
  - `07-backup-dr-plan.md` - Backup and disaster recovery
  - `07-compliance-matrix.md` - Security control mapping
  - `07-resource-inventory.md` - Deployed resource catalog
  - `07-documentation-index.md` - Document package contents

---

**Mission**: Azure infrastructure engineered by agents—from requirements to deployed templates,
aligned with Well-Architected best practices and Azure Verified Modules.
