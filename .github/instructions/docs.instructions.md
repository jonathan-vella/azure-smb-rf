---
description: "Standards for user-facing documentation and SMB Landing Zone project context"
applyTo: "docs/**/*.md"
---

# Documentation Standards

Instructions for creating and maintaining user-facing documentation in the `docs/` folder.

## Project Context

This repository is the **Azure SMB Landing Zone** — a ready-to-deploy, single-subscription
Azure environment for **Microsoft Partners** migrating small business customers from
on-premises infrastructure to Azure at scale.

Key facts to keep in mind when writing documentation:

- **Target audience:** Microsoft Partners, MSPs, IT consultants (not end customers)
- **Deployment model:** Single Azure subscription, 4 scenarios (baseline / firewall / vpn / full)
- **Cost posture:** Cost-first design; resilience traded for affordability
- **Entry point:** `infra/bicep/smb-landing-zone/deploy.ps1`
- **Agent workflow:** The repo includes the Agentic InfraOps agent set for ongoing evolution

## Structure Requirements

### File Header

Every doc file must start with:

```markdown
# {Title}

> [Current Version](../../VERSION.md) | {One-line description}
```

Adjust the relative path depth based on folder nesting (`../../VERSION.md` from `docs/`,
`../../../VERSION.md` from `docs/subfolder/`).

### Single H1 Rule

Each file has exactly ONE H1 heading (the title). Use H2+ for all other sections.

### Link Style

- Use relative links for internal docs (example pattern: `Quickstart -> quickstart.md`)
- For root file references, increase `../` depth based on folder nesting (for example: `../VERSION.md`,
  `../../VERSION.md`)
- Use reference-style links for external URLs
- No broken links (validated in CI)

## Current Architecture (as of 2026-02-18)

### Agents (9 top-level + 5 subagents)

| Agent                | Purpose                                             |
| -------------------- | --------------------------------------------------- |
| `infraops-conductor` | Master orchestrator with approval gates             |
| `requirements`       | Gather SMB landing zone infrastructure requirements |
| `architect`          | WAF assessment and architecture design              |
| `design`             | Architecture diagrams and ADRs                      |
| `bicep-plan`         | Implementation planning and governance discovery    |
| `bicep-code`         | Bicep template generation (AVM-first)               |
| `deploy`             | Azure deployment execution via deploy.ps1           |
| `as-built`           | Step 7 workload documentation suite                 |
| `diagnose`           | Post-deployment health diagnostics                  |

### Subagents (in `_subagents/`)

| Subagent                        | Parent     | Purpose                         |
| ------------------------------- | ---------- | ------------------------------- |
| `cost-estimate-subagent`        | Architect  | Azure Pricing MCP queries       |
| `governance-discovery-subagent` | Bicep Plan | Azure Policy REST API discovery |
| `bicep-lint-subagent`           | Bicep Code | Syntax validation               |
| `bicep-review-subagent`         | Bicep Code | AVM/security code review        |
| `bicep-whatif-subagent`         | Deploy     | Deployment preview              |

### Skills (8 total)

| Skill                 | Category            | Purpose                                    |
| --------------------- | ------------------- | ------------------------------------------ |
| `azure-adr`           | Document Creation   | Architecture Decision Records              |
| `azure-artifacts`     | Artifact Generation | Template H2s, styling, generation rules    |
| `azure-defaults`      | Azure Conventions   | Regions, naming, AVM, WAF, pricing, tags   |
| `azure-diagrams`      | Document Creation   | Python architecture diagrams               |
| `github-operations`   | Workflow Automation | GitHub issues, PRs, CLI, Actions, releases |
| `git-commit`          | Tool Integration    | Commit conventions                         |
| `docs-writer`         | Documentation       | Repo-aware docs maintenance                |
| `make-skill-template` | Meta                | Skill creation helper                      |

### Deployment Scenarios

| Scenario   | Firewall | VPN | NAT GW | Monthly Cost |
| ---------- | :------: | :-: | :----: | -----------: |
| `baseline` |    ❌    | ❌  |   ✅   |         ~$48 |
| `firewall` |    ✅    | ❌  |   ❌   |        ~$336 |
| `vpn`      |    ❌    | ✅  |   ❌   |        ~$187 |
| `full`     |    ✅    | ✅  |   ❌   |        ~$476 |

### Bicep Modules (`infra/bicep/smb-landing-zone/modules/`)

| Module                      | Purpose                              |
| --------------------------- | ------------------------------------ |
| `networking-hub.bicep`      | Hub VNet, Bastion, Private DNS, NSGs |
| `networking-spoke.bicep`    | Spoke VNet, NSG, NAT Gateway         |
| `networking-peering*.bicep` | VNet peering and UDR                 |
| `firewall.bicep`            | Azure Firewall (AVM)                 |
| `vpn-gateway.bicep`         | VPN Gateway (AVM)                    |
| `monitoring.bicep`          | Log Analytics Workspace              |
| `backup.bicep`              | Recovery Services Vault              |
| `budget.bicep`              | Cost Management budget               |
| `migrate.bicep`             | Azure Migrate project                |

## Prohibited References

Do NOT reference these items that do not exist in this repository:

- ❌ `contoso-patient-portal` — belongs to parent Agentic InfraOps repo
- ❌ `diagram.agent.md` → Use `azure-diagrams` skill
- ❌ `adr.agent.md` → Use `azure-adr` skill
- ❌ `docs.agent.md` → Use `azure-artifacts` skill or `as-built` agent
- ❌ `azure-workload-docs` skill → Use `azure-artifacts` skill
- ❌ `azure-deployment-preflight` skill → Merged into deploy agent
- ❌ `orchestration-helper` skill → Deleted (absorbed into conductor)
- ❌ `github-issues` / `github-pull-requests` skills → Use `github-operations`
- ❌ `gh-cli` skill → Merged into `github-operations`
- ❌ `_shared/` directory → Use `azure-defaults` + `azure-artifacts` skills
- ❌ `docs/prompt-guide/` → Does not exist in this repo
- ❌ `docs/workflow.md` → Does not exist in this repo

## Content Principles

| Principle           | Application                                                               |
| ------------------- | ------------------------------------------------------------------------- |
| **Partner-first**   | Write for Microsoft Partners deploying on behalf of SMB customers         |
| **DRY**             | Single source of truth per topic                                          |
| **Current state**   | No historical context in main docs                                        |
| **Action-oriented** | Every section answers "how do I...?"                                      |
| **Minimal**         | If it doesn't help partners deploy today, remove it                       |
| **Cost-aware**      | Always surface monthly cost impact when discussing infrastructure choices |

## Validation

Documentation is validated in CI (warn-only):

- No references to removed agents or non-existent paths
- Version numbers match `VERSION.md` (repo root)
- No broken internal links (`npm run lint:links`)
- Markdown lint passes (`npm run lint:md`)
