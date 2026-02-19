# SMB Ready Foundation

Azure SMB Ready Foundation pattern optimized for VMware-to-Azure migrations for SMB customers.

## Project Type

Infrastructure/Platform (not application)

## Pattern Characteristics

- **Repeatable**: Designed for 1000+ customer deployments
- **Cost-optimized**: Resilience traded for cost savings
- **Secure by default**: Policy-enforced guardrails
- **Migration-ready**: Azure Migrate project pre-configured

## Workflow Status

| Step | Artifact                | Status      | Version |
| ---- | ----------------------- | ----------- | ------- |
| 1    | Requirements            | ✅ Complete | v0.1    |
| 2    | Architecture Assessment | ✅ Complete | v0.1    |
| 3    | Design Artifacts        | ✅ Complete | v0.1    |
| 4    | Implementation Plan     | ✅ Complete | v0.2    |
| 5    | Bicep Code              | ✅ Complete | v0.3    |
| 6    | Deployment              | ✅ Complete | v0.1    |
| 7    | As-Built Documentation  | ✅ Complete | v0.1    |

## Quick Start

```bash
# Use the SMB Ready Foundation prompt with Requirements agent
# Ctrl+Shift+A → Requirements → paste prompt from:
# .github/prompts/plan-smb-ready-foundation.prompt.md
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
