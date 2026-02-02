# Partner Quick Reference Card

> **Azure SMB Landing Zone v0.3.0** | Single-page deployment guide for Microsoft Partners

---

## 📋 Prerequisites Checklist

| Requirement          | Details                                                                                                                 |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| ☐ Docker Desktop     | Or Podman, Colima, Rancher Desktop                                                                                      |
| ☐ VS Code            | With [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension |
| ☐ GitHub Copilot     | Active subscription required                                                                                            |
| ☐ Azure Subscription | Owner role required                                                                                                     |

---

## 🚀 Deploy in 5 Minutes

```bash
# 1. Clone repository
git clone https://github.com/jonathan-vella/azure-agentic-smb-lz.git
cd azure-agentic-smb-lz

# 2. Open in VS Code → F1 → "Dev Containers: Reopen in Container"

# 3. Authenticate (in Dev Container terminal)
az login
az account set --subscription "<your-subscription-id>"

# 4. Deploy (choose one)
cd infra/bicep/smb-landing-zone
./deploy.ps1 -Scenario baseline    # ~4 min, ~$48/mo
./deploy.ps1 -Scenario firewall    # ~15 min, ~$336/mo
./deploy.ps1 -Scenario vpn         # ~25 min, ~$187/mo
./deploy.ps1 -Scenario full        # ~45 min, ~$476/mo
```

---

## 💰 Scenario Comparison

| Scenario     | Use Case                        | Deploy Time | Monthly Cost |
| ------------ | ------------------------------- | ----------- | ------------ |
| **baseline** | Testing, cloud-only workloads   | ~4 min      | ~$48         |
| **firewall** | Egress filtering, compliance    | ~15 min     | ~$336        |
| **vpn**      | Hybrid connectivity, migrations | ~25 min     | ~$187        |
| **full**     | Enterprise: filtering + hybrid  | ~45 min     | ~$476        |

---

## 📦 What Gets Deployed

### All Scenarios Include

- Hub + Spoke VNet topology
- NAT Gateway (outbound internet)
- Azure Bastion Developer (secure VM access)
- Private DNS Zone (auto-registration)
- Log Analytics (500 MB/day cap)
- Recovery Services Vault (VM backup)
- Azure Migrate Project
- 20 Azure Policy guardrails
- Monthly budget alert ($500)

### Scenario-Specific

| Resource            | baseline | firewall | vpn | full |
| ------------------- | :------: | :------: | :-: | :--: |
| Azure Firewall      |    ❌    |    ✅    | ❌  |  ✅  |
| VPN Gateway         |    ❌    |    ❌    | ✅  |  ✅  |
| Hub-Spoke Peering   |    ❌    |    ✅    | ✅  |  ✅  |
| User-Defined Routes |    ❌    |    ✅    | ❌  |  ✅  |

---

## 🧹 Cleanup

Remove all resources when done testing:

```powershell
cd infra/bicep/smb-landing-zone/scripts
./Remove-SmbLandingZone.ps1 -Location swedencentral -Force
```

> ⏱️ Cleanup takes 10-15 minutes

---

## 🆘 Support

| Issue                 | Solution                                                                       |
| --------------------- | ------------------------------------------------------------------------------ |
| Container won't start | Check Docker running, increase memory to 4GB+                                  |
| Azure auth fails      | Try `az login --use-device-code`                                               |
| Deployment fails      | Check subscription has Owner role                                              |
| Need help             | [Open an issue](https://github.com/jonathan-vella/azure-agentic-smb-lz/issues) |

---

## 🔗 Quick Links

- [Full Documentation](../README.md)
- [Architecture Diagrams](images/)
- [Deployment Artifacts](../agent-output/smb-landing-zone/)
- [Bicep Templates](../infra/bicep/smb-landing-zone/)

---

<div align="center">

**Version 0.3.0** | [GitHub](https://github.com/jonathan-vella/azure-agentic-smb-lz) |
MIT License

</div>
