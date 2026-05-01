import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  Button,
  Field,
  Input,
  Spinner,
} from "@fluentui/react-components";
import {
  CheckmarkCircle24Filled,
  ErrorCircle24Filled,
  Circle24Regular,
} from "@fluentui/react-icons";
import { api } from "../api";
import { acquireArmTokenForTenant } from "../auth";

interface DelegationPayload {
  registrationDefinitionId: string;
  registrationDefinitionName: string;
  description: string;
  managedByTenantId: string;
  authorizations: Array<{
    principalId: string;
    principalIdDisplayName: string;
    roleDefinitionId: string;
  }>;
}

interface SubscriptionLookup {
  subscriptionDisplayName: string | null;
  existingCustomer: { id: string; displayName: string; tenantId: string } | null;
}

interface TenantLookup {
  tenantDisplayName: string | null;
  defaultDomainName: string | null;
  // Populated client-side when the API lookup returns null but the public
  // OpenID configuration confirms the tenant exists.
  oidcResolved?: boolean;
  oidcRegion?: string | null;
  oidcIssuer?: string | null;
  // Populated when neither the API nor OIDC discovery could resolve the tenant.
  unresolved?: boolean;
}

type StepStatus = "pending" | "running" | "done" | "failed";
interface Step {
  key: string;
  label: string;
  status: StepStatus;
  detail?: string;
}

const STEP_DEFS: Array<Pick<Step, "key" | "label">> = [
  { key: "preflight", label: "Pre-flight: validate inputs and check duplicates" },
  { key: "payload", label: "Fetch delegation payload" },
  { key: "signin", label: "Sign in to customer tenant" },
  { key: "subaccess", label: "Verify access to customer subscription" },
  { key: "rp", label: "Register Microsoft.ManagedServices RP" },
  { key: "existing", label: "Check for existing delegation" },
  { key: "definition", label: "Create registration definition" },
  { key: "defwait", label: "Wait for definition to provision" },
  { key: "assignment", label: "Create registration assignment" },
  { key: "propagate", label: "Wait for propagation to partner tenant" },
  { key: "persist", label: "Persist customer record" },
];

// Curated list of Azure regions partners typically deploy SMB foundations
// into. Region selection is now handled on the per-customer Prerequisites
// page — onboarding only does Lighthouse delegation.

export function OnboardCustomerPage() {
  const nav = useNavigate();
  const [displayName, setDisplayName] = useState("");
  const [displayNameTouched, setDisplayNameTouched] = useState(false);
  const [subscriptionId, setSubscriptionId] = useState("");
  const [customerTenantId, setCustomerTenantId] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lookup, setLookup] = useState<SubscriptionLookup | null>(null);
  const [lookupBusy, setLookupBusy] = useState(false);
  const [tenantLookup, setTenantLookup] = useState<TenantLookup | null>(null);
  const [tenantLookupBusy, setTenantLookupBusy] = useState(false);
  const [steps, setSteps] = useState<Step[]>(
    STEP_DEFS.map((s) => ({ ...s, status: "pending" })),
  );

  // Refs holding the latest lookup results so debounced lookups can compose
  // a display-name suggestion without depending on stale React state inside
  // their async closures.
  const tenantLookupRef = useRef<TenantLookup | null>(null);
  const subLookupRef = useRef<SubscriptionLookup | null>(null);
  const displayNameTouchedRef = useRef(false);
  const displayNameRef = useRef("");
  const subReqIdRef = useRef(0);
  const tenantReqIdRef = useRef(0);
  const GUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
  useEffect(() => { tenantLookupRef.current = tenantLookup; }, [tenantLookup]);
  useEffect(() => { subLookupRef.current = lookup; }, [lookup]);
  useEffect(() => { displayNameTouchedRef.current = displayNameTouched; }, [displayNameTouched]);
  useEffect(() => { displayNameRef.current = displayName; }, [displayName]);

  // The display name field is disabled until both lookups have either
  // returned a value or are confirmed empty (i.e. no GUID entered yet, or
  // the lookup is still running). This prevents the user from typing into
  // the field only to have it overwritten by a late-arriving suggestion.
  const subFieldFilled = GUID_RE.test(subscriptionId.trim());
  const tenantFieldFilled = GUID_RE.test(customerTenantId.trim());
  const subSettled = !subFieldFilled || (lookup !== null && !lookupBusy);
  const tenantSettled = !tenantFieldFilled || (tenantLookup !== null && !tenantLookupBusy);
  const displayNameReady = subSettled && tenantSettled && (subFieldFilled || tenantFieldFilled);

  // Auto-suggest the display name once *both* lookups have settled, so the
  // suggestion always reflects the combined `<tenant>/<subscription>` rather
  // than whichever lookup happened to finish first. After the field is
  // populated (suggestion or user edit), `maybeSuggestDisplayName` won't
  // overwrite it.
  useEffect(() => {
    if (displayNameTouched) return;
    if (!displayNameReady) return;
    maybeSuggestDisplayName(tenantLookup, lookup);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lookup, tenantLookup, displayNameReady, displayNameTouched]);

  function update(key: string, status: StepStatus, detail?: string) {
    setSteps((prev) =>
      prev.map((s) => (s.key === key ? { ...s, status, detail } : s)),
    );
  }

  // Surfaces both:
  //  - duplicate (already in Cosmos): hard-block onboarding.
  //  - subscription display name (only visible if the partner already has a
  //    delegation on this sub; useful for re-onboarding flows).
  async function lookupSubscription(sub: string) {
    setLookup(null);
    subLookupRef.current = null;
    if (!sub.trim()) return;
    const reqId = ++subReqIdRef.current;
    setLookupBusy(true);
    try {
      const result = await api<SubscriptionLookup>(
        `/customers/lookup/${encodeURIComponent(sub.trim())}`,
      );
      if (reqId !== subReqIdRef.current) return; // newer request superseded us
      setLookup(result);
      subLookupRef.current = result;
    } catch {
      // best-effort — don't block the user
    } finally {
      if (reqId === subReqIdRef.current) setLookupBusy(false);
    }
  }

  // Tries Microsoft Graph (via the API) first; if the partner UAMI lacks
  // CrossTenantInformation.ReadBasic.All the displayName comes back null, so
  // we fall back to a public, unauthenticated OpenID configuration probe
  // that at least confirms the tenant exists and surfaces its region/issuer.
  async function lookupTenant(tenant: string) {
    setTenantLookup(null);
    tenantLookupRef.current = null;
    const t = tenant.trim();
    if (!t) return;
    if (!GUID_RE.test(t)) return;
    const reqId = ++tenantReqIdRef.current;
    setTenantLookupBusy(true);
    try {
      // Run Graph + OIDC discovery in parallel so the slowest call is the
      // ceiling, not the sum. OIDC discovery is essentially instant; the
      // Graph call dominates and benefits from being kicked off immediately.
      const apiPromise = api<TenantLookup>(
        `/customers/lookup-tenant/${encodeURIComponent(t)}`,
      ).catch(() => ({ tenantDisplayName: null, defaultDomainName: null } as TenantLookup));
      const oidcPromise = fetch(
        `https://login.microsoftonline.com/${encodeURIComponent(t)}/v2.0/.well-known/openid-configuration`,
      ).then(async (r) => {
        if (!r.ok) return { ok: false } as const;
        const j = (await r.json()) as { issuer?: string; tenant_region_scope?: string };
        return { ok: true, issuer: j.issuer ?? null, region: j.tenant_region_scope ?? null } as const;
      }).catch(() => ({ ok: false } as const));
      const [apiResult, oidc] = await Promise.all([apiPromise, oidcPromise]);
      if (reqId !== tenantReqIdRef.current) return;
      let result: TenantLookup = apiResult;
      if (!result.tenantDisplayName) {
        if (oidc.ok) {
          result = { ...result, oidcResolved: true, oidcIssuer: oidc.issuer, oidcRegion: oidc.region };
        } else {
          result = { ...result, unresolved: true };
        }
      }
      setTenantLookup(result);
      tenantLookupRef.current = result;
    } finally {
      if (reqId === tenantReqIdRef.current) setTenantLookupBusy(false);
    }
  }

  // Debounced auto-lookup so paste / browser autofill triggers resolution
  // without waiting for an explicit blur. 300 ms is short enough to feel
  // instant on paste yet long enough to avoid a flurry of requests during
  // typing.
  useEffect(() => {
    const v = subscriptionId.trim();
    if (!v) { setLookup(null); subLookupRef.current = null; return; }
    if (!GUID_RE.test(v)) return;
    const handle = setTimeout(() => { void lookupSubscription(v); }, 300);
    return () => clearTimeout(handle);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [subscriptionId]);
  useEffect(() => {
    const v = customerTenantId.trim();
    if (!v) { setTenantLookup(null); tenantLookupRef.current = null; return; }
    if (!GUID_RE.test(v)) return;
    const handle = setTimeout(() => { void lookupTenant(v); }, 300);
    return () => clearTimeout(handle);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [customerTenantId]);

  // Auto-fill display name from tenant + subscription names, but only if the
  // user hasn't typed a value of their own. Reads the touched flag through a
  // ref so the function works correctly when called from async closures.
  function maybeSuggestDisplayName(
    t: TenantLookup | null,
    s: SubscriptionLookup | null,
  ) {
    if (displayNameTouchedRef.current) return;
    const tn = t?.tenantDisplayName?.trim() || null;
    // Fall back to OIDC-derived domain when Graph display name is missing —
    // better than nothing for the auto-suggested label.
    const tnFallback = t?.oidcIssuer
      ? new URL(t.oidcIssuer).hostname.split(".")[0] || null
      : null;
    const sn = s?.subscriptionDisplayName?.trim() || null;
    const tenantPart = tn || tnFallback;
    let suggestion = "";
    if (tenantPart && sn) suggestion = `${tenantPart}/${sn}`;
    else if (sn) suggestion = sn;
    else if (tenantPart) suggestion = tenantPart;
    if (!suggestion) return;
    // Only fill the field while it's still empty. Once a suggestion (or a
    // user edit) has produced a value, never overwrite it from later lookups.
    if (displayNameRef.current.trim()) return;
    setDisplayName(suggestion);
  }

  async function armPut(
    armToken: string,
    url: string,
    body: unknown,
  ): Promise<Response> {
    return fetch(url, {
      method: "PUT",
      headers: {
        Authorization: `Bearer ${armToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
  }

  async function go() {
    setBusy(true);
    setError(null);
    const allSteps = STEP_DEFS;
    setSteps(allSteps.map((s) => ({ ...s, status: "pending" })));

    let currentKey: string | null = null;
    const start = (key: string) => {
      currentKey = key;
      update(key, "running");
    };
    const done = (key: string, detail?: string) => update(key, "done", detail);
    const fail = (key: string, detail: string) => update(key, "failed", detail);

    try {
      // Run a pre-flight check before doing *any* ARM work. The backend
      // lookup catches duplicates (same subscription already onboarded) and
      // we validate the user's GUID inputs locally so we don't get a popup
      // for a typo'd tenant id.
      start("preflight");
      const guid = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
      const sub = subscriptionId.trim();
      const tid = customerTenantId.trim();
      if (!guid.test(sub)) {
        throw new Error(`Subscription ID '${sub}' is not a valid GUID.`);
      }
      if (!guid.test(tid)) {
        throw new Error(`Customer tenant ID '${tid}' is not a valid GUID.`);
      }
      if (!displayName.trim()) {
        throw new Error("Display name is required.");
      }
      const pre = await api<SubscriptionLookup>(
        `/customers/lookup/${encodeURIComponent(sub)}`,
      );
      setLookup(pre);
      if (pre.existingCustomer) {
        throw new Error(
          `Subscription ${sub} is already onboarded as '${pre.existingCustomer.displayName}'. ` +
            `Open the existing customer instead of re-onboarding.`,
        );
      }
      done(
        "preflight",
        pre.subscriptionDisplayName
          ? `'${pre.subscriptionDisplayName}' — not yet onboarded`
          : "not yet onboarded",
      );

      start("payload");
      const payload = await api<DelegationPayload>("/lighthouse/payload");
      done("payload");

      start("signin");
      const armToken = await acquireArmTokenForTenant(customerTenantId, {
        domainHint: tenantLookupRef.current?.defaultDomainName ?? null,
      });

      // Validate the popup picked an account in the *expected* customer tenant.
      const tokenTid = (() => {
        try {
          const [, payloadB64] = armToken.split(".");
          const json = JSON.parse(
            atob(payloadB64.replace(/-/g, "+").replace(/_/g, "/")),
          ) as { tid?: string };
          return json.tid ?? "";
        } catch {
          return "";
        }
      })();
      if (
        tokenTid &&
        tokenTid.toLowerCase() !== customerTenantId.trim().toLowerCase()
      ) {
        throw new Error(
          `Signed-in account is in tenant ${tokenTid}, but the customer tenant is ${customerTenantId}. Please sign in with an account from the customer tenant.`,
        );
      }
      done("signin");

      start("subaccess");
      const subUrl = `https://management.azure.com/subscriptions/${subscriptionId}?api-version=2022-12-01`;
      const subResp = await fetch(subUrl, {
        headers: { Authorization: `Bearer ${armToken}` },
      });
      if (!subResp.ok) {
        const detail = await subResp.text();
        if (subResp.status === 401 || subResp.status === 403) {
          throw new Error(
            `The signed-in account does not have access to subscription ${subscriptionId}. ` +
              `An Owner role is required to deploy the Lighthouse delegation. (${detail})`,
          );
        }
        throw new Error(
          `Subscription lookup failed: ${subResp.status} ${detail}`,
        );
      }
      done("subaccess");

      const apiVersion = "2022-10-01";
      const defUrl =
        `https://management.azure.com/subscriptions/${subscriptionId}` +
        `/providers/Microsoft.ManagedServices/registrationDefinitions/${payload.registrationDefinitionId}` +
        `?api-version=${apiVersion}`;
      const assignUrl =
        `https://management.azure.com/subscriptions/${subscriptionId}` +
        `/providers/Microsoft.ManagedServices/registrationAssignments/${payload.registrationDefinitionId}` +
        `?api-version=${apiVersion}`;

      start("rp");
      const rpRegisterUrl =
        `https://management.azure.com/subscriptions/${subscriptionId}` +
        `/providers/Microsoft.ManagedServices/register?api-version=2021-04-01`;
      const rpResp = await fetch(rpRegisterUrl, {
        method: "POST",
        headers: { Authorization: `Bearer ${armToken}` },
      });
      if (!rpResp.ok && rpResp.status !== 409) {
        throw new Error(
          `RP registration failed: ${rpResp.status} ${await rpResp.text()}`,
        );
      }
      const rpStateUrl =
        `https://management.azure.com/subscriptions/${subscriptionId}` +
        `/providers/Microsoft.ManagedServices?api-version=2021-04-01`;
      const rpDeadline = Date.now() + 2 * 60_000;
      let rpState = "Unknown";
      while (Date.now() < rpDeadline) {
        const stateResp = await fetch(rpStateUrl, {
          headers: { Authorization: `Bearer ${armToken}` },
        });
        if (stateResp.ok) {
          rpState = ((await stateResp.json()) as { registrationState: string })
            .registrationState;
          if (rpState === "Registered") break;
          update("rp", "running", `state: ${rpState}`);
        }
        await new Promise((r) => setTimeout(r, 3000));
      }
      done("rp", rpState);

      start("existing");
      const existingAssignmentsUrl =
        `https://management.azure.com/subscriptions/${subscriptionId}` +
        `/providers/Microsoft.ManagedServices/registrationAssignments` +
        `?api-version=${apiVersion}&$expand=registrationDefinition`;
      const existingResp = await fetch(existingAssignmentsUrl, {
        headers: { Authorization: `Bearer ${armToken}` },
      });
      if (existingResp.ok) {
        const existing = (await existingResp.json()) as {
          value?: Array<{
            properties?: {
              registrationDefinition?: {
                properties?: { managedByTenantId?: string };
              };
            };
          }>;
        };
        const otherPartner = existing.value?.find(
          (a) =>
            a.properties?.registrationDefinition?.properties
              ?.managedByTenantId &&
            a.properties.registrationDefinition.properties.managedByTenantId.toLowerCase() !==
              payload.managedByTenantId.toLowerCase(),
        );
        if (otherPartner) {
          throw new Error(
            `Subscription ${subscriptionId} is already delegated to a different partner tenant ` +
              `(${otherPartner.properties?.registrationDefinition?.properties?.managedByTenantId}). ` +
              `Remove that delegation in Azure Portal → Service providers before re-onboarding.`,
          );
        }
      }
      done("existing");

      start("definition");
      const defResp = await armPut(armToken, defUrl, {
        properties: {
          registrationDefinitionName: payload.registrationDefinitionName,
          description: payload.description,
          managedByTenantId: payload.managedByTenantId,
          authorizations: payload.authorizations,
        },
      });
      if (!defResp.ok) {
        const defErrText = await defResp.text();
        // Azure returns RegistrationDefinitionInvalidUpdate (HTTP 400) when a
        // registrationDefinition with the same GUID already exists on the
        // subscription but points at a *different* managedByTenantId — i.e.
        // the subscription is already delegated to another partner tenant
        // (or to a stale copy of this offer that we can no longer overwrite).
        // Surface a clear, actionable message instead of the raw ARM JSON.
        if (
          defResp.status === 400 &&
          /RegistrationDefinitionInvalidUpdate|ManagedByTenantId not allowed to update/i.test(
            defErrText,
          )
        ) {
          throw new Error(
            `Subscription ${subscriptionId} is already delegated via Azure Lighthouse to a different ` +
              `partner tenant, so its registration definition cannot be updated from this console. ` +
              `In the customer's Azure Portal, go to "Service providers" → "Service provider offers", ` +
              `remove the existing delegation, and then retry onboarding.`,
          );
        }
        throw new Error(
          `registrationDefinition PUT failed: ${defResp.status} ${defErrText}`,
        );
      }
      const defJson = (await defResp.json()) as { id: string };
      done("definition");

      // ARM rejects the assignment PUT until the definition transitions to
      // 'Succeeded' (otherwise: 409 InvalidRegistrationAssignmentCreateRequest).
      start("defwait");
      const defDeadline = Date.now() + 3 * 60_000;
      let defState = "Unknown";
      while (Date.now() < defDeadline) {
        const stateResp = await fetch(defUrl, {
          headers: { Authorization: `Bearer ${armToken}` },
        });
        if (stateResp.ok) {
          const cur = (await stateResp.json()) as {
            properties?: { provisioningState?: string };
          };
          defState = cur.properties?.provisioningState ?? "Unknown";
          if (defState === "Succeeded") break;
          if (defState === "Failed" || defState === "Canceled") {
            throw new Error(`registrationDefinition provisioning ${defState}`);
          }
          update("defwait", "running", `state: ${defState}`);
        }
        await new Promise((r) => setTimeout(r, 3000));
      }
      done("defwait", defState);

      start("assignment");
      const assignResp = await armPut(armToken, assignUrl, {
        properties: { registrationDefinitionId: defJson.id },
      });
      if (
        !assignResp.ok &&
        assignResp.status !== 201 &&
        assignResp.status !== 200
      ) {
        throw new Error(
          `registrationAssignment PUT failed: ${assignResp.status} ${await assignResp.text()}`,
        );
      }
      done("assignment");

      // Best-effort: give ARM ~60s to replicate the assignment to the partner
      // tenant. The API persists regardless and the worker (running as the
      // partner UAMI) surfaces any real propagation issues at deploy time.
      start("propagate");
      const deadline = Date.now() + 60_000;
      let delegated = false;
      let lastErr = "";
      while (Date.now() < deadline) {
        try {
          const r = await api<{ delegated: boolean }>(
            `/lighthouse/verify?subscriptionId=${encodeURIComponent(subscriptionId)}`,
          );
          if (r.delegated) {
            delegated = true;
            break;
          }
        } catch (e) {
          lastErr = e instanceof Error ? e.message : String(e);
        }
        await new Promise((r) => setTimeout(r, 5000));
      }
      done(
        "propagate",
        delegated
          ? "visible from partner tenant"
          : lastErr || "not yet visible (continuing)",
      );

      start("persist");
      const partnerTenantId = import.meta.env.VITE_TENANT_ID as string;
      const created = await api<{ id: string }>("/customers", {
        method: "POST",
        body: JSON.stringify({
          subscriptionId,
          customerTenantId,
          partnerTenantId,
          displayName,
        }),
      });
      done("persist");

      nav(`/customers/${created.id}?tenantId=${customerTenantId}`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      if (currentKey) fail(currentKey, msg);
      setError(msg);
    } finally {
      setBusy(false);
    }
  }

  function StepIcon({ status }: { status: StepStatus }) {
    switch (status) {
      case "done":
        return (
          <CheckmarkCircle24Filled
            primaryFill="#107c10"
            aria-label="completed"
          />
        );
      case "running":
        return <Spinner size="tiny" aria-label="running" />;
      case "failed":
        return (
          <ErrorCircle24Filled primaryFill="#a4262c" aria-label="failed" />
        );
      default:
        return <Circle24Regular aria-label="pending" />;
    }
  }

  const anyStarted = steps.some((s) => s.status !== "pending");

  // Auto-scroll the steps panel so the currently running (or most recently
  // failed) step stays in view as the wizard progresses.
  const stepRefs = useRef<Record<string, HTMLLIElement | null>>({});
  useEffect(() => {
    if (!anyStarted) return;
    const active =
      steps.find((s) => s.status === "running") ??
      steps.find((s) => s.status === "failed") ??
      [...steps].reverse().find((s) => s.status === "done");
    if (!active) return;
    const el = stepRefs.current[active.key];
    el?.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }, [steps, anyStarted]);

  return (
    <div>
      <h1>Onboard a customer</h1>
      <p>
        The customer admin will be prompted to sign in once so the partner
        management console can deploy the Lighthouse delegation directly into
        their subscription.
      </p>
      <div
        style={{
          display: "flex",
          gap: 24,
          alignItems: "flex-start",
          flexWrap: "wrap",
        }}
      >
        <div style={{ flex: "1 1 420px", maxWidth: 480, minWidth: 320 }}>
      <Field label="Customer subscription ID">
        <Input
          value={subscriptionId}
          onChange={(_, d) => {
            setSubscriptionId(d.value);
            setLookup(null);
          }}
          onBlur={() => lookupSubscription(subscriptionId)}
        />
      </Field>
      {lookupBusy && <small>Checking subscription…</small>}
      {lookup?.subscriptionDisplayName && (
        <p style={{ color: "#107c10", margin: "4px 0" }}>
          Subscription name: <strong>{lookup.subscriptionDisplayName}</strong>
        </p>
      )}
      {lookup?.existingCustomer && (
        <div
          style={{
            margin: "8px 0",
            padding: 12,
            border: "1px solid #a4262c",
            background: "#fde7e9",
            borderRadius: 4,
          }}
        >
          <strong>Already onboarded</strong> as{" "}
          <em>{lookup.existingCustomer.displayName}</em>.{" "}
          <a
            href={`/customers/${lookup.existingCustomer.id}?tenantId=${lookup.existingCustomer.tenantId}`}
          >
            Open existing customer
          </a>
        </div>
      )}
      <Field label="Customer tenant ID">
        <Input
          value={customerTenantId}
          onChange={(_, d) => {
            setCustomerTenantId(d.value);
            setTenantLookup(null);
          }}
          onBlur={() => lookupTenant(customerTenantId)}
        />
      </Field>
      {tenantLookupBusy && <small>Checking tenant…</small>}
      {tenantLookup?.tenantDisplayName && (
        <p style={{ color: "#107c10", margin: "4px 0" }}>
          Tenant: <strong>{tenantLookup.tenantDisplayName}</strong>
          {tenantLookup.defaultDomainName && (
            <> ({tenantLookup.defaultDomainName})</>
          )}
        </p>
      )}
      {tenantLookup &&
        !tenantLookup.tenantDisplayName &&
        tenantLookup.oidcResolved && (
          <p style={{ color: "#797775", margin: "4px 0", fontSize: 12 }}>
            Tenant exists
            {tenantLookup.oidcRegion ? <> ({tenantLookup.oidcRegion})</> : null}
            . Display name unavailable — grant the partner identity Microsoft
            Graph <code>CrossTenantInformation.ReadBasic.All</code> to resolve
            tenant names automatically.
          </p>
        )}
      {tenantLookup?.unresolved && (
        <p style={{ color: "#a4262c", margin: "4px 0", fontSize: 12 }}>
          Tenant could not be resolved. Verify the GUID is a real Microsoft
          Entra tenant id.
        </p>
      )}
      <Field
        label="Display name"
        hint={
          displayNameReady
            ? "Auto-suggested from the tenant and subscription names. Edit to override."
            : "Enter the customer subscription and tenant IDs above. The display name will fill in automatically."
        }
      >
        <Input
          value={displayName}
          disabled={!displayNameReady}
          onChange={(_, d) => {
            setDisplayName(d.value);
            setDisplayNameTouched(true);
          }}
        />
      </Field>
      <div style={{ marginTop: 12 }}>
        <Button
          appearance="primary"
          disabled={busy || !!lookup?.existingCustomer}
          onClick={go}
        >
          Start onboarding
        </Button>
      </div>

      {error && (
        <p style={{ marginTop: 16, color: "#a4262c" }}>
          <strong>Error:</strong> {error}
        </p>
      )}
        </div>

        {anyStarted && (
          <div
            style={{
              flex: "1 1 360px",
              minWidth: 320,
              maxHeight: "calc(100vh - 220px)",
              overflowY: "auto",
              padding: 16,
              border: "1px solid var(--border, #444)",
              borderRadius: 4,
              position: "sticky",
              top: 16,
            }}
          >
            <h2 style={{ marginTop: 0, fontSize: 16 }}>Onboarding steps</h2>
            <ol
              style={{
                listStyle: "none",
                padding: 0,
                margin: 0,
                display: "flex",
                flexDirection: "column",
                gap: 8,
              }}
            >
              {steps.map((s) => {
                const muted = s.status === "pending";
                return (
                  <li
                    key={s.key}
                    ref={(el) => {
                      stepRefs.current[s.key] = el;
                    }}
                    style={{
                      display: "flex",
                      alignItems: "center",
                      gap: 12,
                      opacity: muted ? 0.5 : 1,
                      fontWeight: s.status === "running" ? 600 : 400,
                    }}
                  >
                    <span
                      style={{
                        width: 24,
                        height: 24,
                        display: "inline-flex",
                        alignItems: "center",
                        justifyContent: "center",
                        flexShrink: 0,
                      }}
                    >
                      <StepIcon status={s.status} />
                    </span>
                    <span>
                      {s.label}
                      {s.detail && (
                        <span
                          style={{
                            marginLeft: 8,
                            color:
                              s.status === "failed" ? "#a4262c" : "#605e5c",
                            fontWeight: 400,
                            fontSize: 12,
                          }}
                        >
                          — {s.detail}
                        </span>
                      )}
                    </span>
                  </li>
                );
              })}
            </ol>
          </div>
        )}
      </div>
    </div>
  );
}
