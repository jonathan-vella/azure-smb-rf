import { useEffect, useState } from "react";
import { useParams, useSearchParams, Link } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  Button,
  Spinner,
  MessageBar,
  MessageBarBody,
  MessageBarTitle,
  Input,
  Field,
} from "@fluentui/react-components";
import { api } from "../api";
import { acquireArmTokenForTenant } from "../auth";
import { REGION_LABELS, normalizeAllowedRegions } from "../regions";
import { RegionPicker, RegionMultiPicker } from "../RegionPicker";

interface Customer {
  id: string;
  tenantId: string;
  subscriptionId: string;
  displayName: string;
  policyMiResourceId?: string | null;
  prerequisites?: PrerequisitesState | null;
}

interface PrerequisitesState {
  managementGroupId?: string | null;
  templateVersion?: string | null;
  lastDeploymentName?: string | null;
  correlationId?: string | null;
  deployedAt?: string | null;
  status?: string | null;
  allowedRegions?: string[] | null;
}

interface TemplateResponse {
  version: string;
  sourceRepo: string;
  templatePath: string;
  template: unknown;
}

interface DelegationCheck {
  ok: boolean;
  subscriptionDisplayName?: string;
  error?: string;
  message?: string;
}

/**
 * Customer-prerequisites page: deploys the smb-rf management group, the
 * MG-scope policy initiative, and the customer-tenant policy MI used by the
 * smb-backup-02 DINE policy. MG-scope ARM ops cannot be Lighthouse-delegated,
 * so the SPA acquires a customer-admin ARM token via popup and PUTs the
 * deployments under that identity.
 */
export function CustomerPrerequisitesPage() {
  const { id } = useParams();
  const [sp] = useSearchParams();
  const tenantId = sp.get("tenantId") ?? "";
  const qc = useQueryClient();

  const [mgIdOverride, setMgIdOverride] = useState("");
  const [progress, setProgress] = useState<string[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [primaryRegion, setPrimaryRegion] = useState<string>("swedencentral");
  const [allowedRegions, setAllowedRegions] = useState<string[]>([
    "swedencentral",
    "germanywestcentral",
  ]);

  const customer = useQuery({
    queryKey: ["customer", id, tenantId],
    queryFn: () => api<Customer>(`/customers/${id}?tenantId=${tenantId}`),
  });

  // Best-effort tenant lookup so we can pass `domain_hint` to the customer
  // ARM popup. Skips home-realm discovery and prevents AAD from silently
  // re-using a cached account from another customer tenant.
  const tenantLookup = useQuery({
    queryKey: ["tenant-lookup", customer.data?.tenantId],
    queryFn: () =>
      api<{ tenantDisplayName: string | null; defaultDomainName: string | null }>(
        `/customers/lookup-tenant/${encodeURIComponent(customer.data!.tenantId)}`,
      ).catch(() => ({ tenantDisplayName: null, defaultDomainName: null })),
    enabled: Boolean(customer.data?.tenantId),
    staleTime: 5 * 60_000,
  });

  // Live delegation probe — gates the deploy button when the customer has
  // revoked the Lighthouse offer.
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

  const template = useQuery({
    queryKey: ["foundation-template"],
    queryFn: () =>
      api<TemplateResponse>(`/prerequisites/template?refresh=true`),
    staleTime: 0,
  });

  const recordOutcome = useMutation({
    mutationFn: (body: {
      managementGroupId: string;
      templateVersion: string;
      deploymentName: string;
      correlationId?: string;
      status: "Pending" | "Succeeded" | "Failed";
      allowedRegions?: string[];
      policyMiResourceId?: string;
    }) =>
      api(`/customers/${id}/prerequisites?tenantId=${tenantId}`, {
        method: "POST",
        body: JSON.stringify(body),
      }),
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ["customer", id, tenantId] }),
  });

  // Seed the region pickers from any previously-recorded prerequisites so the
  // operator sees the live config, not the hardcoded defaults.
  useEffect(() => {
    const persisted = customer.data?.prerequisites?.allowedRegions;
    if (persisted && persisted.length > 0) {
      const editable = persisted.filter((r) => r !== "global");
      if (editable.length > 0) {
        setAllowedRegions(editable);
        if (!editable.includes(primaryRegion)) setPrimaryRegion(editable[0]);
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [customer.data?.prerequisites?.allowedRegions?.join(",")]);

  const deployInteractive = async () => {
    setError(null);
    setProgress([]);
    if (!customer.data || !template.data) return;
    const c = customer.data;
    const tpl = template.data;
    const mgId = (mgIdOverride || c.tenantId).trim();
    const deploymentName = `smb-rf-prereq-${new Date()
      .toISOString()
      .replace(/[-:T.Z]/g, "")
      .slice(0, 14)}`;
    const effectiveAllowedRegions = normalizeAllowedRegions(
      allowedRegions,
      primaryRegion,
    );

    const log = (msg: string) =>
      setProgress((p) => [...p, `[${new Date().toLocaleTimeString()}] ${msg}`]);

    try {
      log("Requesting ARM token from customer tenant...");
      const armToken = await acquireArmTokenForTenant(c.tenantId, {
        domainHint: tenantLookup.data?.defaultDomainName ?? null,
      });

      // Verify the token came from the right tenant before we touch ARM.
      const tid = parseTid(armToken);
      if (tid && tid !== c.tenantId) {
        throw new Error(
          `Signed-in account is in tenant ${tid}, expected ${c.tenantId}.`,
        );
      }
      log(`Got ARM token for tenant ${c.tenantId}`);

      const url =
        `https://management.azure.com/providers/Microsoft.Management/managementGroups/` +
        `${encodeURIComponent(mgId)}/providers/Microsoft.Resources/deployments/` +
        `${encodeURIComponent(deploymentName)}?api-version=2021-04-01`;

      const body = {
        location: primaryRegion,
        properties: {
          mode: "Incremental",
          template: tpl.template,
          parameters: {
            subscriptionId: { value: c.subscriptionId },
          },
        },
      };

      log(`Submitting MG deployment '${deploymentName}' to ${mgId}...`);
      const putResp = await fetch(url, {
        method: "PUT",
        headers: {
          Authorization: `Bearer ${armToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });
      if (!putResp.ok) {
        const t = await putResp.text();
        throw new Error(`ARM PUT failed: ${putResp.status} ${t}`);
      }
      const submitted = (await putResp.json()) as ArmDeployment;
      const correlationId = submitted.properties?.correlationId;
      log(`Accepted (correlationId ${correlationId ?? "n/a"}). Polling...`);

      // Persist a Pending row so the UI reflects in-flight state if the user
      // closes the tab before completion.
      await recordOutcome.mutateAsync({
        managementGroupId: mgId,
        templateVersion: tpl.version,
        deploymentName,
        correlationId,
        status: "Pending",
        allowedRegions: effectiveAllowedRegions,
      });

      // Poll for terminal state.
      const final = await pollDeployment(url, armToken, log);
      const succeeded = final.properties?.provisioningState === "Succeeded";
      log(
        succeeded
          ? "Prerequisites MG deployment succeeded."
          : `MG deployment ended with state: ${final.properties?.provisioningState}`,
      );

      // Re-deploy the policy initiative on smb-rf MG so the allowed-regions
      // list (and any other policy params) match what the operator just
      // selected. Doing this here means "Update prerequisites" is also
      // "update allowed regions" — same flow, same RBAC requirements.
      if (succeeded) {
        log("Fetching policy initiative template...");
        const polTpl = await api<{ version: string; template: unknown }>(
          `/prerequisites/policy-template?refresh=true`,
        );
        const policyMgId = "smb-rf";
        const policyDeploymentName = `smb-rf-policy-${new Date()
          .toISOString()
          .replace(/[-:T.Z]/g, "")
          .slice(0, 14)}`;
        const policyMgUrl =
          `https://management.azure.com/providers/Microsoft.Management/managementGroups/` +
          `${encodeURIComponent(policyMgId)}/providers/Microsoft.Resources/deployments/` +
          `${encodeURIComponent(policyDeploymentName)}?api-version=2021-04-01`;
        log(
          `Submitting policy initiative '${policyDeploymentName}' to ${policyMgId} (regions: ${effectiveAllowedRegions.join(", ")})...`,
        );
        const polResp = await fetch(policyMgUrl, {
          method: "PUT",
          headers: {
            Authorization: `Bearer ${armToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            location: primaryRegion,
            properties: {
              mode: "Incremental",
              template: polTpl.template,
              parameters: {
                allowedLocations: { value: effectiveAllowedRegions },
              },
            },
          }),
        });
        if (!polResp.ok) {
          throw new Error(
            `Policy initiative PUT failed: ${polResp.status} ${await polResp.text()}`,
          );
        }
        const polFinal = await pollDeployment(policyMgUrl, armToken, log);
        const polSucceeded =
          polFinal.properties?.provisioningState === "Succeeded";
        log(
          polSucceeded
            ? "Policy initiative deployment succeeded."
            : `Policy initiative ended with state: ${polFinal.properties?.provisioningState}`,
        );
        if (!polSucceeded) {
          throw new Error(
            `Policy initiative deployment ended with state: ${polFinal.properties?.provisioningState}`,
          );
        }
      }

      // ----- Policy-MI sub-scope deployment (customer-admin context) -----
      // The smb-backup-02 DINE policy needs Backup Contributor + VM
      // Contributor at sub scope. Lighthouse-delegated UAA cannot grant
      // those to a customer-tenant SystemAssigned MI, so we deploy a UAMI
      // here under the same customer-admin ARM token used for the MG ops.
      // The customer record's policyMiResourceId is then persisted with the
      // prerequisites outcome so the worker can wire it into deployments.
      let policyMiResourceId: string | undefined;
      if (succeeded) {
        log("Fetching policy MI onboarding template...");
        const pmiTpl = await api<{ version: string; template: unknown }>(
          `/prerequisites/policy-mi-template?refresh=true`,
        );
        const pmiDeploymentName = `smb-rf-policy-mi-${new Date()
          .toISOString()
          .replace(/[-:T.Z]/g, "")
          .slice(0, 14)}`;
        const pmiUrl =
          `https://management.azure.com/subscriptions/${c.subscriptionId}` +
          `/providers/Microsoft.Resources/deployments/${encodeURIComponent(pmiDeploymentName)}` +
          `?api-version=2021-04-01`;
        log(
          `Submitting policy MI deployment '${pmiDeploymentName}' to subscription ${c.subscriptionId} (region: ${primaryRegion})...`,
        );
        const pmiResp = await fetch(pmiUrl, {
          method: "PUT",
          headers: {
            Authorization: `Bearer ${armToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            location: primaryRegion,
            properties: {
              mode: "Incremental",
              template: pmiTpl.template,
              parameters: { location: { value: primaryRegion } },
            },
          }),
        });
        if (!pmiResp.ok) {
          throw new Error(
            `Policy MI deployment PUT failed: ${pmiResp.status} ${await pmiResp.text()}`,
          );
        }
        const pmiFinal = await pollDeployment(pmiUrl, armToken, log);
        const pmiState = pmiFinal.properties?.provisioningState;
        if (pmiState !== "Succeeded") {
          throw new Error(
            `Policy MI deployment ended with state: ${pmiState}`,
          );
        }
        policyMiResourceId =
          pmiFinal.properties?.outputs?.policyMiResourceId?.value;
        if (!policyMiResourceId) {
          throw new Error(
            "Policy MI deployment succeeded but no resourceId in outputs.",
          );
        }
        log(`Policy MI deployment succeeded: ${policyMiResourceId}`);
      }

      await recordOutcome.mutateAsync({
        managementGroupId: mgId,
        templateVersion: tpl.version,
        deploymentName,
        correlationId,
        status: succeeded ? "Succeeded" : "Failed",
        allowedRegions: effectiveAllowedRegions,
        policyMiResourceId,
      });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      setError(msg);
      log(`ERROR: ${msg}`);
    }
  };

  const f = customer.data?.prerequisites;
  const latestVersion = template.data?.version;
  const deployedVersion = f?.templateVersion ?? null;
  const updateAvailable = !!(
    f &&
    f.status === "Succeeded" &&
    latestVersion &&
    deployedVersion &&
    deployedVersion !== latestVersion
  );
  const isInitialDeploy = !f || f.status === "Failed";
  const deployButtonLabel = isInitialDeploy
    ? "Deploy prerequisites"
    : updateAvailable
      ? "Update prerequisites"
      : "Re-deploy prerequisites";

  const delegationOk = delegation.data?.ok === true;
  const deployBlocked = !customer.data || !template.data || !delegationOk;

  return (
    <div>
      <h1>{customer.data?.displayName} — Prerequisites</h1>
      <p>
        <Link to={`/customers/${id}?tenantId=${tenantId}`}>
          ← Back to customer
        </Link>
      </p>

      {delegation.isLoading && (
        <MessageBar intent="info">
          <Spinner size="tiny" />
          <MessageBarBody style={{ marginLeft: 8 }}>
            Verifying Lighthouse delegation…
          </MessageBarBody>
        </MessageBar>
      )}
      {delegation.data && !delegation.data.ok && (
        <MessageBar intent="error" style={{ marginBottom: 16 }}>
          <MessageBarBody>
            <MessageBarTitle>Delegation revoked or missing</MessageBarTitle>
            {delegation.data.message ??
              "The partner UAMI cannot read this subscription. Re-onboard the customer (Lighthouse offer) before deploying prerequisites."}
          </MessageBarBody>
        </MessageBar>
      )}

      <section style={{ marginTop: 16, marginBottom: 24 }}>
        <h2>Status</h2>
        {!f && (
          <MessageBar intent="warning">
            <MessageBarBody>
              <MessageBarTitle>Not deployed</MessageBarTitle>
              The smb-rf management group has not been bootstrapped for this
              customer yet.
            </MessageBarBody>
          </MessageBar>
        )}
        {f && (
          <MessageBar
            intent={
              f.status === "Succeeded"
                ? "success"
                : f.status === "Failed"
                  ? "error"
                  : "info"
            }
          >
            <MessageBarBody style={{ overflowWrap: "anywhere", wordBreak: "break-word" }}>
              <MessageBarTitle>{f.status ?? "Unknown"}</MessageBarTitle>
              MG <code>{f.managementGroupId}</code> · template{" "}
              <code>{f.templateVersion}</code>
              {f.deployedAt && <> · deployed {f.deployedAt}</>}
            </MessageBarBody>
          </MessageBar>
        )}
        {template.data && (
          <p style={{ color: "var(--text-muted)", fontSize: "0.9rem", overflowWrap: "anywhere", wordBreak: "break-word" }}>
            Latest template: <code>{template.data.sourceRepo}</code>@
            <code>{template.data.version}</code> ·{" "}
            <code>{template.data.templatePath}</code>
          </p>
        )}
        {updateAvailable && (
          <MessageBar intent="info" style={{ marginTop: 8 }}>
            <MessageBarBody>
              <MessageBarTitle>Update available</MessageBarTitle>
              Deployed template <code>{deployedVersion}</code> is older than
              the latest <code>{latestVersion}</code>. Use <em>Update
              prerequisites</em> below to redeploy with the current template.
            </MessageBarBody>
          </MessageBar>
        )}
      </section>

      <Field
        label="Parent management group ID (defaults to tenant root)"
        hint="Leave blank to create smb-rf directly under the tenant root MG."
      >
        <Input
          value={mgIdOverride}
          onChange={(_, d) => setMgIdOverride(d.value)}
          placeholder={customer.data?.tenantId ?? ""}
        />
      </Field>

      <Field
        label="Primary region"
        hint="Used as the location for the MG deployment record itself. Always included in the allow list."
      >
        <RegionPicker
          value={primaryRegion}
          onChange={setPrimaryRegion}
        />
      </Field>

      <Field
        label="Allowed regions"
        hint="Resources may only be deployed in these regions. 'global' is always included automatically."
      >
        <RegionMultiPicker
          values={allowedRegions}
          onChange={setAllowedRegions}
        />
      </Field>

      {f?.allowedRegions && f.allowedRegions.length > 0 && (
        <p style={{ color: "var(--text-muted)", fontSize: "0.85rem" }}>
          Currently effective:{" "}
          {f.allowedRegions
            .map((r) => REGION_LABELS[r] ?? r)
            .join(", ")}
        </p>
      )}

      <div style={{ marginTop: 16 }}>
        <p>
          Signs you in as a customer admin via popup and submits the MG
          deployment under that identity. The admin needs{" "}
          <em>Management Group Contributor</em> (or Owner) on the parent
          management group.
        </p>
        <Button
          appearance="primary"
          onClick={deployInteractive}
          disabled={deployBlocked}
        >
          {deployButtonLabel}
        </Button>
        {!template.data && template.isFetching && (
          <Spinner size="tiny" label="Loading template..." />
        )}
        {template.isError && (
          <MessageBar intent="error" style={{ marginTop: 12 }}>
            <MessageBarBody>
              <MessageBarTitle>Failed to load prerequisites template</MessageBarTitle>
              {(template.error as Error).message}
              <div style={{ marginTop: 8 }}>
                <Button size="small" onClick={() => template.refetch()}>
                  Retry
                </Button>
              </div>
            </MessageBarBody>
          </MessageBar>
        )}
        {!customer.data && customer.isError && (
          <MessageBar intent="error" style={{ marginTop: 12 }}>
            <MessageBarBody>
              <MessageBarTitle>Failed to load customer</MessageBarTitle>
              {(customer.error as Error).message}
            </MessageBarBody>
          </MessageBar>
        )}
        {progress.length > 0 && (
          <pre
            style={{
              marginTop: 16,
              padding: 12,
              background: "var(--surface-2)",
              borderRadius: 6,
              fontSize: "0.85rem",
              maxHeight: 320,
              overflow: "auto",
            }}
          >
            {progress.join("\n")}
          </pre>
        )}
      </div>

      {error && (
        <MessageBar intent="error" style={{ marginTop: 16 }}>
          <MessageBarBody>
            <MessageBarTitle>Error</MessageBarTitle>
            {error}
          </MessageBarBody>
        </MessageBar>
      )}
    </div>
  );
}

interface ArmDeployment {
  properties?: {
    provisioningState?: string;
    correlationId?: string;
    error?: { code?: string; message?: string };
    outputs?: Record<string, { value?: string }>;
  };
}

async function pollDeployment(
  url: string,
  armToken: string,
  log: (msg: string) => void,
): Promise<ArmDeployment> {
  const terminal = new Set(["Succeeded", "Failed", "Canceled"]);
  for (let i = 0; i < 120; i++) {
    await new Promise((r) => setTimeout(r, 5000));
    const resp = await fetch(url, {
      headers: { Authorization: `Bearer ${armToken}` },
    });
    if (!resp.ok) {
      log(`Poll failed: ${resp.status}`);
      continue;
    }
    const body = (await resp.json()) as ArmDeployment;
    const state = body.properties?.provisioningState ?? "Unknown";
    log(`State: ${state}`);
    if (terminal.has(state)) return body;
  }
  throw new Error("Deployment polling timed out after 10 minutes.");
}

function parseTid(token: string): string | null {
  try {
    const payload = token.split(".")[1];
    const json = JSON.parse(
      atob(payload.replace(/-/g, "+").replace(/_/g, "/")),
    );
    return typeof json.tid === "string" ? json.tid : null;
  } catch {
    return null;
  }
}
