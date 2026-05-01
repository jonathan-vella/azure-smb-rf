import { useEffect, useMemo, useState } from "react";
import { useParams, useSearchParams, useNavigate } from "react-router-dom";
import {
  Button,
  Dropdown,
  Field,
  Input,
  MessageBar,
  MessageBarBody,
  MessageBarTitle,
  Option,
  Spinner,
} from "@fluentui/react-components";
import { useQuery } from "@tanstack/react-query";
import { api } from "../api";
import { RegionPicker } from "../RegionPicker";

const SCENARIOS = ["baseline", "firewall", "vpn", "full"] as const;
type Scenario = (typeof SCENARIOS)[number];

// Foundation main.bicep restricts `environment` to these values.
const ENV_NAMES = ["dev", "staging", "prod"] as const;
type EnvName = (typeof ENV_NAMES)[number];

// Allowed forward transitions. A scenario is only "locked in" by a prior
// *succeeded* deployment for the same environment — failures don't count.
// Re-deploying the same scenario is always allowed (it's effectively an
// idempotent rerun); the rule the partner asked for is "no going back to a
// less complete topology."
const ALLOWED_NEXT: Record<Scenario, readonly Scenario[]> = {
  baseline: ["baseline", "firewall", "vpn", "full"],
  firewall: ["firewall", "full"],
  vpn: ["vpn", "full"],
  full: ["full"],
};

// API serializes Scenario enum as PascalCase (Baseline / Firewall / Vpn /
// Full) but the SPA, worker and CLI all use lowercase strings. Normalize.
function normalizeScenario(s: string | undefined | null): Scenario | null {
  if (!s) return null;
  const lc = s.toLowerCase();
  return (SCENARIOS as readonly string[]).includes(lc) ? (lc as Scenario) : null;
}

interface DelegationCheck {
  ok: boolean;
  subscriptionDisplayName?: string;
  error?: string;
  message?: string;
}

interface DeploymentRow {
  id: string;
  environmentName: string;
  scenario: string;
  status: string;
  parameters?: Record<string, string>;
  createdAt?: string;
  completedAt?: string | null;
}

interface CustomerWithPrerequisites {
  id: string;
  subscriptionId?: string;
  prerequisites?: {
    status?: string | null;
    allowedRegions?: string[] | null;
  } | null;
}

export function DeployPage() {
  const { id } = useParams();
  const [sp] = useSearchParams();
  const tenantId = sp.get("tenantId") ?? "";
  const nav = useNavigate();

  const [envName, setEnvName] = useState<EnvName>("prod");
  const [scenario, setScenario] = useState<Scenario>("baseline");
  const [owner, setOwner] = useState("");
  const [region, setRegion] = useState<string>("");
  const [hubCidr, setHubCidr] = useState("10.0.0.0/23");
  const [spokeCidr, setSpokeCidr] = useState("10.0.2.0/23");
  const [onPremCidr, setOnPremCidr] = useState("");
  const [logCapGb, setLogCapGb] = useState("0.5");
  const [budgetAmount, setBudgetAmount] = useState("500");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Live probe: can the partner UAMI read this subscription? If not, the
  // worker won't be able to deploy either, so block the user up-front.
  const delegation = useQuery({
    queryKey: ["delegation-check", id, tenantId],
    queryFn: () =>
      api<DelegationCheck>(
        `/customers/${id}/delegation-check?tenantId=${encodeURIComponent(tenantId)}`,
      ),
    enabled: Boolean(id && tenantId),
    staleTime: 60_000,
    retry: false,
  });

  // History — used to lock previously-deployed parameters and constrain the
  // scenario picker so the operator can't accidentally regress to a less
  // complete topology.
  const deployments = useQuery({
    queryKey: ["deployments", id],
    queryFn: () => api<DeploymentRow[]>(`/deployments/${id}`),
    enabled: Boolean(id),
  });

  // Pull the customer to get the prerequisites + allowed-regions list.
  // The deploy region dropdown is derived from that list (minus 'global')
  // so a partner cannot pick a region the policy initiative would reject.
  const customer = useQuery({
    queryKey: ["customer", id, tenantId],
    queryFn: () =>
      api<CustomerWithPrerequisites>(
        `/customers/${id}?tenantId=${encodeURIComponent(tenantId)}`,
      ),
    enabled: Boolean(id && tenantId),
  });

  const regionOptions = useMemo(() => {
    const list = (customer.data?.prerequisites?.allowedRegions ?? []).filter(
      (r) => r !== "global",
    );
    return list;
  }, [customer.data?.prerequisites?.allowedRegions]);

  const prerequisitesReady =
    customer.data?.prerequisites?.status === "Succeeded";

  // Default to the first allowed region once the prerequisites load.
  useEffect(() => {
    if (!region && regionOptions.length > 0) setRegion(regionOptions[0]);
  }, [regionOptions, region]);

  // Most recent *succeeded* deployment for the currently-selected env name.
  // Failed runs don't establish a baseline because nothing actually got
  // deployed — the partner can re-pick CIDRs / scenario freely.
  const lastSucceeded = useMemo<DeploymentRow | null>(() => {
    const list = deployments.data;
    if (!list) return null;
    const matching = list
      .filter(
        (d) =>
          d.environmentName === envName &&
          d.status?.toLowerCase() === "succeeded",
      )
      .sort((a, b) => {
        const ta = Date.parse(a.completedAt ?? a.createdAt ?? "") || 0;
        const tb = Date.parse(b.completedAt ?? b.createdAt ?? "") || 0;
        return tb - ta;
      });
    return matching[0] ?? null;
  }, [deployments.data, envName]);

  const lockedHub = lastSucceeded?.parameters?.HUB_VNET_ADDRESS_SPACE ?? null;
  const lockedSpoke =
    lastSucceeded?.parameters?.SPOKE_VNET_ADDRESS_SPACE ?? null;
  // On-prem CIDR is only meaningful for vpn/full; we still lock it so a
  // partner cannot silently retarget the local network gateway across
  // redeploys.
  const lockedOnPrem =
    lastSucceeded?.parameters?.ON_PREMISES_ADDRESS_SPACE ?? null;
  // Region is locked once an environment has succeeded — same reason as the
  // CIDRs: redeploying a different region would not extend the existing
  // network, it would build a parallel one.
  const lockedRegion = lastSucceeded?.parameters?.LOCATION ?? null;
  const lockedOwner = lastSucceeded?.parameters?.OWNER ?? null;
  const prevScenario = normalizeScenario(lastSucceeded?.scenario);
  const allowedScenarios: readonly Scenario[] = prevScenario
    ? ALLOWED_NEXT[prevScenario]
    : SCENARIOS;

  // When the env-name selection changes (or history first loads) seed the
  // form fields from the previous successful deployment so the locked values
  // are visible to the user and the picker reflects the constrained set.
  useEffect(() => {
    if (lastSucceeded) {
      if (lockedHub) setHubCidr(lockedHub);
      if (lockedSpoke) setSpokeCidr(lockedSpoke);
      if (lockedOnPrem) setOnPremCidr(lockedOnPrem);
      if (lockedRegion) setRegion(lockedRegion);
      // Owner is locked too — changing the resource owner across redeploys
      // would orphan the tag-based cost views.
      if (lockedOwner) setOwner(lockedOwner);
      const prevLogCap = lastSucceeded.parameters?.LOG_ANALYTICS_DAILY_CAP_GB;
      if (prevLogCap) setLogCapGb(prevLogCap);
      const prevBudget = lastSucceeded.parameters?.BUDGET_AMOUNT;
      if (prevBudget) setBudgetAmount(prevBudget);
      // If current scenario isn't in the allowed set, snap to the previous
      // one (always allowed) so the Dropdown shows a sensible value.
      if (prevScenario && !allowedScenarios.includes(scenario)) {
        setScenario(prevScenario);
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lastSucceeded?.id]);

  async function submit() {
    setBusy(true);
    setError(null);
    try {
      const trimmedOwner = owner.trim();
      if (!trimmedOwner) {
        throw new Error("Owner email is required (used for resource tagging).");
      }
      // Defensive: if the user managed to bypass the dropdown filtering
      // (e.g. via React-Query refetch races), reject the submit instead of
      // letting the worker tear down a more-complete topology.
      if (prevScenario && !ALLOWED_NEXT[prevScenario].includes(scenario)) {
        throw new Error(
          `Cannot transition from '${prevScenario}' back to '${scenario}'.`,
        );
      }
      // Server-side enforcement happens via the same parameters dictionary
      // — overriding the locked CIDRs is rejected here for clarity.
      const hub = lockedHub ?? hubCidr;
      const spoke = lockedSpoke ?? spokeCidr;
      const onPrem = (lockedOnPrem ?? onPremCidr).trim();
      const requiresOnPrem = scenario === "vpn" || scenario === "full";
      if (requiresOnPrem && !onPrem) {
        throw new Error(
          `Scenario '${scenario}' requires an on-premises address space (e.g. '192.168.0.0/16').`,
        );
      }
      const budget = budgetAmount.trim();
      if (!/^\d+$/.test(budget)) {
        throw new Error("Budget amount must be a positive integer (USD).");
      }
      const logCap = logCapGb.trim();
      if (!/^\d+(\.\d+)?$/.test(logCap)) {
        throw new Error("Log Analytics daily cap must be a number (GB).");
      }
      const effectiveRegion = lockedRegion ?? region;
      if (!effectiveRegion) {
        throw new Error(
          "No region selected. Add at least one allowed region to the customer prerequisites first.",
        );
      }
      if (!prerequisitesReady) {
        throw new Error(
          "Customer prerequisites are not deployed. Deploy them before running scenarios.",
        );
      }
      if (!delegation.data?.ok) {
        throw new Error(
          "Lighthouse delegation is missing or revoked. Re-onboard the customer.",
        );
      }
      const parameters: Record<string, string> = {
        OWNER: trimmedOwner,
        LOCATION: effectiveRegion,
        HUB_VNET_ADDRESS_SPACE: hub,
        SPOKE_VNET_ADDRESS_SPACE: spoke,
        LOG_ANALYTICS_DAILY_CAP_GB: logCap,
        BUDGET_AMOUNT: budget,
      };
      if (onPrem) parameters.ON_PREMISES_ADDRESS_SPACE = onPrem;
      const created = await api<{ id: string }>("/deployments", {
        method: "POST",
        body: JSON.stringify({
          customerId: id,
          customerTenantId: tenantId,
          environmentName: envName,
          scenario,
          parameters,
        }),
      });
      nav(`/customers/${id}/deployments/${created.id}`);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div style={{ maxWidth: 600 }}>
      <h1>Deploy</h1>

      {delegation.isLoading && (
        <MessageBar intent="info">
          <Spinner size="tiny" />
          <MessageBarBody style={{ marginLeft: 8 }}>
            Verifying Lighthouse delegation…
          </MessageBarBody>
        </MessageBar>
      )}
      {delegation.isError && (
        <MessageBar intent="error">
          <MessageBarBody>
            <MessageBarTitle>Delegation check failed</MessageBarTitle>
            {(delegation.error as Error).message}
          </MessageBarBody>
        </MessageBar>
      )}
      {delegation.data && !delegation.data.ok && (
        <MessageBar intent="error">
          <MessageBarBody>
            <MessageBarTitle>Partner UAMI cannot access this subscription</MessageBarTitle>
            {delegation.data.message ??
              "The Lighthouse delegation appears to be missing or revoked. Re-onboard the customer before deploying."}
          </MessageBarBody>
        </MessageBar>
      )}
      {delegation.data?.ok && delegation.data.subscriptionDisplayName && (
        <MessageBar intent="success">
          <MessageBarBody>
            Connected to <strong>{delegation.data.subscriptionDisplayName}</strong>.
          </MessageBarBody>
        </MessageBar>
      )}

      {customer.isSuccess && !prerequisitesReady && (
        <MessageBar intent="warning" style={{ marginTop: 8 }}>
          <MessageBarBody>
            <MessageBarTitle>Prerequisites not deployed</MessageBarTitle>
            Deploy the customer prerequisites (management group + policy
            initiative) before running scenarios.
          </MessageBarBody>
        </MessageBar>
      )}

      {lastSucceeded && (
        <MessageBar intent="info" style={{ marginTop: 8 }}>
          <MessageBarBody>
            <MessageBarTitle>Existing environment</MessageBarTitle>
            <code>{envName}</code> was last deployed as{" "}
            <code>{prevScenario}</code>. Network ranges are locked; you can
            advance the scenario but not go back.
          </MessageBarBody>
        </MessageBar>
      )}

      <Field label="Environment name">
        <Dropdown
          value={envName}
          selectedOptions={[envName]}
          onOptionSelect={(_, d) => {
            const next = (d.optionValue ?? "") as EnvName;
            if ((ENV_NAMES as readonly string[]).includes(next)) setEnvName(next);
          }}
        >
          {ENV_NAMES.map((x) => (
            <Option key={x} value={x}>
              {x}
            </Option>
          ))}
        </Dropdown>
      </Field>
      <Field label="Scenario">
        <Dropdown
          value={scenario}
          selectedOptions={[scenario]}
          onOptionSelect={(_, d) => {
            const next = (d.optionValue ?? "") as Scenario;
            if (allowedScenarios.includes(next)) setScenario(next);
          }}
        >
          {SCENARIOS.map((x) => {
            const blocked = !allowedScenarios.includes(x);
            const label =
              blocked && prevScenario
                ? `${x} (not allowed from ${prevScenario})`
                : x;
            return (
              <Option key={x} value={x} text={label} disabled={blocked}>
                {label}
              </Option>
            );
          })}
        </Dropdown>
      </Field>
      <Field
        label="Region"
        hint={
          lockedRegion
            ? "Locked — established by the first successful deployment for this environment."
            : regionOptions.length === 0
              ? "No allowed regions configured on the customer prerequisites."
              : "Pick from the regions allowed by the customer prerequisites policy."
        }
      >
        <RegionPicker
          subscriptionId={customer.data?.subscriptionId}
          allowedIds={lockedRegion ? [lockedRegion] : regionOptions}
          value={lockedRegion ?? region}
          disabled={!!lockedRegion || regionOptions.length === 0}
          onChange={setRegion}
        />
      </Field>
      <Field
        label="Owner email"
        required
        hint={
          lockedOwner
            ? "Locked — established by the first successful deployment for this environment."
            : undefined
        }
      >
        <Input
          value={owner}
          onChange={(_, d) => setOwner(d.value)}
          required
          readOnly={!!lockedOwner}
          disabled={!!lockedOwner}
        />
      </Field>
      <Field
        label="Hub VNet CIDR"
        hint={
          lockedHub
            ? "Locked — established by the first successful deployment for this environment."
            : undefined
        }
      >
        <Input
          value={hubCidr}
          onChange={(_, d) => setHubCidr(d.value)}
          readOnly={!!lockedHub}
          disabled={!!lockedHub}
        />
      </Field>
      <Field
        label="Spoke VNet CIDR"
        hint={
          lockedSpoke
            ? "Locked — established by the first successful deployment for this environment."
            : undefined
        }
      >
        <Input
          value={spokeCidr}
          onChange={(_, d) => setSpokeCidr(d.value)}
          readOnly={!!lockedSpoke}
          disabled={!!lockedSpoke}
        />
      </Field>
      {(scenario === "vpn" || scenario === "full" || lockedOnPrem) && (
        <Field
          label="On-premises address space"
          required={scenario === "vpn" || scenario === "full"}
          hint={
            lockedOnPrem
              ? "Locked — established by the first successful deployment for this environment."
              : "CIDR of the on-premises network the VPN gateway will route to (e.g. 192.168.0.0/16)."
          }
        >
          <Input
            value={onPremCidr}
            onChange={(_, d) => setOnPremCidr(d.value)}
            placeholder="192.168.0.0/16"
            readOnly={!!lockedOnPrem}
            disabled={!!lockedOnPrem}
          />
        </Field>
      )}
      <Field
        label="Log Analytics daily cap (GB)"
        hint="Caps daily ingestion to control cost. 0.5 ≈ 500 MB/day."
      >
        <Input
          type="number"
          step={0.1}
          min={0}
          value={logCapGb}
          onChange={(_, d) => setLogCapGb(d.value)}
        />
      </Field>
      <Field
        label="Monthly budget (USD)"
        hint="Cost Management budget; alerts fire at 80% / 100% / 120%."
      >
        <Input
          type="number"
          step={50}
          min={0}
          value={budgetAmount}
          onChange={(_, d) => setBudgetAmount(d.value)}
        />
      </Field>
      <div style={{ marginTop: 12 }}>
        <Button
          appearance="primary"
          disabled={busy || delegation.isLoading || !delegation.data?.ok || !prerequisitesReady}
          onClick={submit}
        >
          Deploy
        </Button>
      </div>
      {error && <p style={{ color: "crimson" }}>{error}</p>}
    </div>
  );
}
