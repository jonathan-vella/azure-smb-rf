# SMB Landing Zone

Azure landing zone pattern optimized for VMware-to-Azure migrations for SMB customers.

## Project Type

Infrastructure/Platform (not application)

## Pattern Characteristics

- **Repeatable**: Designed for 1000+ customer deployments
- **Cost-optimized**: Resilience traded for cost savings
- **Secure by default**: Policy-enforced guardrails
- **Migration-ready**: Azure Migrate project pre-configured

## Workflow Status

| Step | Artifact                | Status     |
| ---- | ----------------------- | ---------- |
| 1    | Requirements            | ⏳ Pending |
| 2    | Architecture Assessment | ⏳ Pending |
| 3    | Design Artifacts        | ⏳ Pending |
| 4    | Implementation Plan     | ⏳ Pending |
| 5    | Bicep Code              | ⏳ Pending |
| 6    | Deployment              | ⏳ Pending |
| 7    | As-Built Documentation  | ⏳ Pending |

## Quick Start

```bash
# Use the SMB Landing Zone prompt with Requirements agent
# Ctrl+Shift+A → Requirements → paste prompt from:
# .github/prompts/plan-smb-landing-zone.prompt.md
```

## Key Decisions

| Decision   | Choice                  | Rationale                    |
| ---------- | ----------------------- | ---------------------------- |
| Resilience | Not required            | Cost priority for SMB        |
| VM Access  | Azure Bastion Developer | No public IPs                |
| Outbound   | NAT Gateway             | Default outbound deprecated  |
| DNS        | Azure Private DNS       | Auto-registration            |
| Backup     | Recovery Services Vault | Post-migration VM protection |

---

_Generated for Agentic InfraOps SMB pattern_
