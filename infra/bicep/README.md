# Bicep Infrastructure Templates

This folder contains Azure Bicep templates for infrastructure deployment.

## Structure

```text
infra/bicep/
├── {project-name}/
│   ├── main.bicep          # Main deployment template
│   ├── main.bicepparam     # Parameter file (defaults)
│   ├── main.parameters.json # azd parameter bridge
│   ├── azure.yaml          # azd project manifest
│   ├── hooks/              # azd lifecycle hooks
│   │   ├── pre-provision.ps1
│   │   └── post-provision.ps1
│   └── modules/            # Reusable modules
│       ├── network.bicep
│       ├── storage.bicep
│       └── ...
```

## Generating Templates

Use the agent workflow:

1. `azure-principal-architect` - Architecture assessment
2. `bicep-plan` - Create implementation plan
3. `bicep-implement` - Generate Bicep code

## Deployment

```bash
# Navigate to project folder
cd infra/bicep/{project-name}

# Configure environment
azd env new {project}-{env}
azd env set SCENARIO baseline
azd env set OWNER partner@contoso.com

# Preview changes
azd provision --preview

# Deploy
azd up
```

## Validation

```bash
# Build (syntax check)
bicep build main.bicep

# Lint (best practices)
bicep lint main.bicep

# Format
bicep format main.bicep
```
