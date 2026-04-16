# Legacy Deployment Scripts (Archived)

These scripts have been replaced by `azd` (Azure Developer CLI) as the deployment mechanism.

## What changed

| Old | New |
|---|---|
| `deploy.ps1` | `azd provision` (with `hooks/pre-provision.ps1`) |
| `deploy-mg.ps1` | Integrated into `hooks/pre-provision.ps1` step 5 |
| `deploy.ps1 -WhatIf` | `azd provision --preview` |
| `deploy.ps1 -Scenario X` | `azd env set SCENARIO X && azd provision` |

## Why archived (not deleted)

- Kept for reference — contains documented retry patterns, CIDR validation, and cleanup logic
- Partners with existing automation may need to review the migration path
- The hooks (`hooks/pre-provision.ps1`, `hooks/post-provision.ps1`) were derived from this code

## Do not use these scripts directly

They will not be maintained. Use the `azd` workflow instead:

```bash
cd infra/bicep/smb-ready-foundation
azd env new smb-rf-baseline
azd env set SCENARIO baseline
azd env set OWNER partner@contoso.com
azd up
```

See the root `README.md` Quick Start for full instructions.
