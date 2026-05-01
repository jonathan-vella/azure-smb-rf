# Plan: Partner Management Console for SMB Ready Foundation

Build a partner-tenant web app (.NET 10 API + React SPA on Azure Container Apps) that onboards customer subscriptions via Azure Lighthouse and deploys `smb-ready-foundation` (Bicep or Terraform) into them. Onboarding uses a one-time interactive partner-admin login to the customer tenant to deploy the Lighthouse delegation template; everything afterwards runs as the console's user-assigned managed identity acting through Lighthouse.

## Architecture (high level)

- **Partner tenant** hosts: Container Apps environment, API, SPA, Container Apps **Job** (deploy worker), Cosmos DB (metadata), Key Vault, Container Registry, Log Analytics, App Insights, user-assigned managed identity (UAMI).
- **Customer subscription** receives: Lighthouse delegation (registration definition + assignment scoping the partner UAMI as `Contributor` + `User Access Administrator` on the subscription), and on first Terraform deploy a bootstrapped Storage Account holding remote state.
- **Onboarding** = interactive popup to customer tenant (partner admin signs in), deploy Lighthouse template, verify delegation, persist customer record.
- **Deployments** = API enqueues a Container Apps Job execution; job clones the repo, runs `azd up` against the customer subscription via Lighthouse-scoped identity, streams logs back through Log Analytics → SignalR to SPA.

## Phases & Steps

### Phase 1 — Console infrastructure (partner tenant)

All console artifacts live under `management-console/` (not under `infra/`):

```text
management-console/
  azure.yaml              # azd manifest (infra.path: infra)
  infra/                  # Bicep for the console itself
    main.bicep
    main.parameters.json
  api/                    # .NET 10 minimal API
  web/                    # React SPA
  worker/                 # Container Apps Job image (Dockerfile + entrypoint)
  lighthouse/             # Customer-side delegation ARM template
```

1. Create `management-console/infra/main.bicep` using AVM modules: ACA env, ACR, Cosmos DB (serverless, SQL API), Key Vault, Log Analytics, App Insights, UAMI, role assignments. _Parallel with steps 2-3._
2. Add `management-console/azure.yaml` with two services (`api`, `web`) and a Container Apps Job for the deploy worker; co-located `.azure/` per the multi-project azd convention.
3. Wire diagnostics, Defender for Containers, private endpoints (optional MVP toggle), HTTPS-only, TLS 1.2 — per the repo's security baseline.

### Phase 2 — Entra ID app registrations (automated via azd hooks)

App registrations are managed by **azd lifecycle hooks** under `management-console/hooks/`,
not provisioned manually. Both run from `azure.yaml` and are idempotent.

4. **`hooks/preprovision.ps1`** (runs before `azd provision`, cross-platform pwsh):
   - Creates/reuses single-tenant **API app reg** `${PROJECT_SHORT}-api-${env}`. Sets identifier
     URI `api://{appId}`, exposes `access_as_user` OAuth2 scope, ensures SP exists.
   - Creates/reuses single-tenant **SPA app reg** `${PROJECT_SHORT}-spa-${env}`. Configures SPA
     platform with localhost redirect, adds delegated permission to API scope, and
     pre-authorizes the SPA on the API (silent consent).
   - Writes `API_APP_CLIENT_ID`, `SPA_APP_CLIENT_ID`, `API_APP_SCOPE_ID`, `AZURE_TENANT_ID`
     into the azd env so `main.parameters.json` resolves them at deploy time.
5. **`hooks/postprovision.ps1`** (runs after `azd provision`, cross-platform pwsh):
   - Reads `WEB_FQDN` / `API_FQDN` Bicep outputs from azd env.
   - Patches the SPA app reg's redirect URIs to `["https://{webFqdn}", "http://localhost:5173"]`
     via Microsoft Graph.
   - Sets `SPA_REDIRECT_URI_PROD`, `SPA_REDIRECT_URI_LOCAL`, `API_BASE_URL` in the azd env.
6. **Lighthouse offer app reg** (multi-tenant) — used only during customer onboarding popup so
   the partner admin can consent in the customer tenant; minimal Graph delegated permissions
   (`User.Read`) plus ARM `user_impersonation` to deploy the Lighthouse template into the
   customer subscription. _Currently provisioned out of band; not in the hook scripts yet._

**Caller prerequisites**: `az login` as a partner-tenant user with `Application Administrator`
or `Application Developer` role to manage app registrations.

### Phase 3 — .NET 10 API backend

7. Scaffold ASP.NET Core minimal API with `Microsoft.Identity.Web` (JWT bearer for SPA tokens). Endpoints group: `/customers`, `/deployments`, `/scenarios`, `/lighthouse`.
8. Cosmos repository layer with containers `customers`, `deployments`, `auditLog`. Partition key = tenant for `customers`, customerId for `deployments`.
9. **Lighthouse onboarding endpoints**: `POST /lighthouse/template` returns the rendered ARM template + redirect URL; `POST /customers` registers a customer after partner confirms delegation succeeded; backend verifies via ARM `GET /subscriptions/{id}/providers/Microsoft.ManagedServices/registrationAssignments` using the partner UAMI.
10. **Deployment endpoints**: `POST /deployments` validates IaC-lock, enqueues a Container Apps Job execution (ARM SDK `ContainerAppsAPIClient.Jobs.StartAsync`) with env vars (`SUBSCRIPTION_ID`, `IAC`, `SCENARIO`, parameter JSON, `CUSTOMER_ID`).
11. **Log streaming**: SignalR hub backed by App Insights/Log Analytics queries (KQL polling) and Job execution status; SPA subscribes per `deploymentId`.
12. **IaC lock enforcement**: first successful deployment writes `iacChoice` on the customer doc with an etag-guarded update; subsequent deploys fail validation if mismatched.
13. **Drift / re-deploy**: `POST /deployments/{id}/redeploy` reuses prior parameters; `GET /deployments/{id}/drift` runs `terraform plan -detailed-exitcode` or `bicep what-if` via the same Job image.

### Phase 4 — React SPA frontend

14. Vite + React + TS + MSAL React + TanStack Query + a UI lib (Fluent UI v9 — fits Microsoft partners).
15. Routes: `/login`, `/customers`, `/customers/:id`, `/customers/:id/deploy`, `/customers/:id/deployments/:depId` (live logs).
16. Onboarding wizard: enter subscription ID → "Authorize in customer tenant" button opens popup to `https://login.microsoftonline.com/{customerTenant}/oauth2/v2.0/authorize` for the multi-tenant Lighthouse app → on consent, SPA calls API which deploys the Lighthouse template at subscription scope → poll until delegation visible → record customer.
17. Deployment wizard: pick environment label (e.g. `dev`, `prod`), pick IaC (locked after first success), pick scenario (`baseline | firewall | vpn | full`), fill parameter form (address spaces, daily cap, owner email) with client-side validation matching `main.bicepparam.reference`.
18. Live log viewer with virtualized list + status pill (Queued → Running → Succeeded/Failed); links to App Insights deep dive.

### Phase 5 — Deploy worker (Container Apps Job)

19. Build a single container image (`mcr.microsoft.com/azure-cli` base + `azd`, `terraform`, `bicep`, PowerShell, `git`). Pushed to partner ACR.
20. Entrypoint script: federated-identity login as the UAMI → `az account set --subscription $SUBSCRIPTION_ID` (works because Lighthouse delegation projects the UAMI into the customer sub) → `git clone` the pinned repo+SHA → `cd infra/{IAC}/smb-ready-foundation` → run `azd up` with env vars sourced from the API payload.
21. **Terraform state bootstrap** (only when `IAC=terraform` and customer is new): job first creates `rg-tfstate-mgmt-{region}`, Storage Account, container `tfstate`, then writes a backend partial-config and runs `terraform init -backend-config=...` against that customer-side storage. Subsequent deploys just `terraform init` against the same backend.
22. Logs → stdout → Log Analytics (auto via ACA); job pushes status updates to a Cosmos `deployments` doc via the API's internal callback endpoint protected by job-only managed identity claim.
23. Idempotency: jobs use a deterministic execution name `{customerId}-{env}-{timestamp}`; the API rejects overlapping in-flight executions per customer/environment.

### Phase 6 — Multi-environment per customer

24. Customer doc holds an `environments[]` array (`name`, `iacChoice`, `scenario`, `parameters`, `lastDeploymentId`, `tfStateContainer`); IaC lock is **per customer** (matches "make it stick once resources are deployed").
25. Naming collisions avoided by suffixing azd env name with `{customerId}-{env}` per the multi-project azd convention.

### Phase 7 — Verification & docs

26. Add `management-console/.azure/plan.md` (azure-prepare output), wire into `npm run validate:all`.
27. Add Playwright smoke test: login → onboard mock customer (Lighthouse template against a test sub) → deploy `baseline` → assert resource groups exist → teardown.
28. Update `docs/partner-quick-reference.md` with a "Use the console" section. **Do not** create new top-level docs unless asked.

## Relevant files

- `infra/bicep/smb-ready-foundation/` — existing Bicep deployment the console invokes; reuse `azure.yaml` shape.
- `infra/terraform/smb-ready-foundation/` — existing Terraform deployment; the worker calls `azd up` here; backend is reconfigured per-customer.
- `infra/bicep/smb-ready-foundation/main.bicepparam.reference` — parameter source-of-truth driving the SPA's parameter form schema.
- `docs/partner-quick-reference.md` — authoritative scenario/cost table; SPA scenario picker should mirror it.
- `scripts/Remove-SmbReadyFoundation.ps1` — out-of-scope for MVP but referenced for future teardown.
- New: `management-console/api/` (.NET 10 minimal API), `management-console/web/` (React SPA), `management-console/worker/` (Dockerfile + entrypoint), `management-console/infra/` (console Bicep), `management-console/lighthouse/` (delegation ARM template), `management-console/azure.yaml`.
- `.github/skills/entra-app-registration/SKILL.md`, `.github/skills/azure-prepare/SKILL.md`, `.github/skills/azure-bicep-patterns/SKILL.md` — load before implementation.

## Verification

1. `npm run validate:all` passes (lint, IaC security baseline, MD).
2. `bicep lint management-console/infra/main.bicep` and `bicep build` succeed.
3. `cd management-console && azd up` deploys the console end-to-end into a clean partner sub.
4. Manual: onboard a test customer subscription → Lighthouse delegation visible in `az rest --method get --url /subscriptions/{id}/providers/Microsoft.ManagedServices/registrationAssignments?api-version=2022-10-01`.
5. Manual: deploy `baseline` Bicep → 6 RGs created in customer sub; deployment status `Succeeded` in console; logs streamed live.
6. Manual: attempt to switch from Bicep to Terraform on same customer — API returns 409 with explanatory message.
7. Manual: deploy `terraform`/`baseline` → state container `tfstate` exists in customer sub Storage Account.
8. Playwright smoke test from step 27 green.

## Decisions

- **Onboarding**: Lighthouse-only; one-time interactive partner-admin login to customer tenant deploys the delegation template. After that, partner-tenant UAMI does everything via Lighthouse.
- **State**: Cosmos DB serverless in partner tenant for app metadata; Terraform state in a per-customer Storage Account in the customer subscription, bootstrapped by the worker on first Terraform deploy.
- **Execution**: Container Apps **Job** per deployment (one image, both Bicep and Terraform).
- **Auth**: Single-tenant SPA + API in the partner tenant; one extra multi-tenant app reg solely for the customer-tenant onboarding popup.
- **IaC lock**: Hard lock per customer-environment after first successful deploy.
- **In scope**: API, SPA, console infra, Entra auth, Lighthouse onboarding, customer registry + IaC lock, scenario picker, Job-based deploys with live logs, deployment history, multi-env per customer, drift/re-deploy.
- **Out of scope (MVP)**: teardown UI, Cost Management dashboards.

## Further Considerations

1. **Lighthouse limitations** — the existing deployment assigns **management-group-scoped policies** and creates a management group. Lighthouse delegation targets a _subscription_ and cannot manage MG resources in the customer tenant. Options:
   - **A (recommended)**: Onboarding template _also_ runs `New-AzManagementGroup` + `New-AzManagementGroupSubscription` and assigns subscription-level policies only; skip MG-scoped policies (or document as a manual customer step). Aligns with most partners' reality.
   - **B**: Require the customer admin to run a second one-time script for MG creation; console detects and warns.
   - **C**: Move all 33 policies to subscription scope in `smb-ready-foundation` (bigger change to the existing project).
2. **SignalR vs polling for log streaming** — A: Azure SignalR Service (cleanest, ~$50/mo). B: in-process SignalR on ACA (cheaper, fine for MVP). C: SSE with EventStream from the API (simplest, no extra service). Recommend **B** for MVP, **A** if partner scales beyond ~100 concurrent viewers.
3. **Worker image hosting** — A: partner ACR (recommended; clean ownership). B: GHCR public image (simpler updates, but ties partners to GitHub). Recommend **A**.
