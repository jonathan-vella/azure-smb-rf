# Partner Management Console

Partner-tenant web app that onboards customer subscriptions via **Azure Lighthouse**
and deploys the [smb-ready-foundation](../infra/) Bicep IaC into them.

> **Provisioning prerequisite — Global Administrator (or equivalent) in the partner tenant.**
>
> `azd up` runs hooks that create Entra app registrations, app roles, an Entra
> security group, and (in `postprovision`) admin-consents the
> `CrossTenantInformation.ReadBasic.All` Microsoft Graph application permission
> to the partner UAMI. That last step requires `AppRoleAssignment.ReadWrite.All`
> and `Application.Read.All` on Microsoft Graph, which in practice means the
> operator running `azd up` must be a **Global Administrator**, **Privileged
> Role Administrator**, or **Cloud Application Administrator** in the partner
> tenant. Without it the hook logs a warning and tenant-name auto-suggestion in
> the onboarding wizard falls back to subscription name only.

## Layout

```text
management-console/
  azure.yaml          # azd manifest
  infra/              # Bicep for the console itself (partner tenant)
  api/                # .NET 10 minimal API
  web/                # React + Fluent UI v9 SPA
  worker/             # Container Apps Job image (azd + bicep)
  lighthouse/         # Customer-side Lighthouse delegation ARM template
```

## Architecture

| Component       | Where                   | Purpose                                                    |
| --------------- | ----------------------- | ---------------------------------------------------------- |
| API             | Partner ACA             | REST endpoints, MSAL auth, SignalR hub                     |
| SPA             | Partner ACA             | React + Fluent UI; signs in partner staff                  |
| Worker (Job)    | Partner ACA Job         | Manual-trigger; runs `azd up` against customer sub         |
| Cosmos DB       | Partner sub             | App metadata (`customers`, `deployments`, `auditLog`)      |
| ACR             | Partner sub             | Holds API/SPA/Worker images                                |
| UAMI            | Partner sub             | Identity used by all 3 services & projected via Lighthouse |
| Lighthouse      | Customer subscription   | Delegates `Contributor` + UAA on the sub to partner UAMI   |

## Onboarding flow

1. Partner staff signs into the SPA (single-tenant Entra app).
2. Enters customer **subscription ID** + **tenant ID**.
3. SPA fetches a rendered Lighthouse delegation template from
   `GET /lighthouse/template`.
4. Partner admin clicks the button; portal opens in the **customer tenant**.
   Admin signs in interactively as a customer Owner and clicks Deploy.
5. SPA polls `GET /lighthouse/verify?subscriptionId=…` until the registration
   assignment is visible. The partner UAMI now has Contributor + UAA on the
   customer subscription via Lighthouse.
6. SPA calls `POST /customers` to persist the record.
7. From here on, **no further customer-tenant logins are needed**.

## Deploy flow

1. Partner picks customer → environment label (e.g. `dev`, `prod`) → scenario
   (`baseline | firewall | vpn | full`) → parameter form.
2. API validates, enqueues a Container Apps Job execution.
3. Worker logs in as the UAMI, sets the customer subscription as active, and
   runs `azd up` against the Bicep foundation.
4. Worker callbacks `POST /deployments/{customerId}/{id}/status` so the SPA
   sees Queued → Running → Succeeded/Failed.
5. SignalR hub `/hubs/deployments` streams logs to the SPA in real time.

## Decisions

- **Onboarding model**: Lighthouse only; one-time interactive partner-admin
  login to the customer tenant for delegation deploy.
- **State**: Cosmos DB in partner tenant (metadata). Bicep is stateless — no
  per-customer state container is required.
- **Execution**: Container Apps **Job** per deployment.
- **Auth**: Single-tenant SPA + API; one multi-tenant app reg solely for
  the customer-tenant onboarding popup.
- **IaC**: Bicep only.
- **Log streaming**: in-process SignalR on ACA (cheap; OK for MVP).
- **Worker image hosting**: partner ACR.

## Open items / known gaps

- The base `smb-ready-foundation` deployment assigns **management-group-scoped
  policies** which Lighthouse cannot delegate. The onboarding template has to
  also create a sub-MG association during the customer-admin step, or those
  policies must move to subscription scope.
- E2E Playwright smoke test, drift detection, and teardown wizard are tracked
  in `agent-output/management-console/01-plan.md` (Phases 6-7).

## Local dev

```bash
# API
cd api && dotnet run

# SPA
cd web && npm install && npm run dev
```

## Deploy the console

```bash
cd management-console
azd env new partner-prod
azd env set OWNER ops@partner.example
azd env set API_APP_CLIENT_ID <api-app-client-id>
azd env set SPA_APP_CLIENT_ID <spa-app-client-id>
azd up
```
