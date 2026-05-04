import { useState } from "react";
import { useParams, useSearchParams, Link } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Badge,
  Button,
  Input,
  MessageBar,
  MessageBarBody,
  MessageBarTitle,
  Table,
  TableBody,
  TableCell,
  TableHeader,
  TableHeaderCell,
  TableRow,
} from "@fluentui/react-components";
import { api } from "../api";

interface Deployment {
  id: string;
  environmentName: string;
  scenario: string;
  status: "Queued" | "Running" | "Succeeded" | "Failed" | "Cancelled";
  createdAt: string;
  startedAt?: string;
  completedAt?: string;
}

interface PrerequisitesState {
  managementGroupId: string;
  templateVersion: string;
  lastDeploymentName: string;
  correlationId?: string;
  deployedAt: string;
  status: "Pending" | "Succeeded" | "Failed";
}

interface DelegationCheck {
  ok: boolean;
  subscriptionDisplayName?: string;
  message?: string;
}

interface Customer {
  displayName: string;
  subscriptionId: string;
  prerequisites?: PrerequisitesState | null;
}

const depColor: Record<
  Deployment["status"],
  "informative" | "success" | "danger" | "warning"
> = {
  Queued: "informative",
  Running: "informative",
  Succeeded: "success",
  Failed: "danger",
  Cancelled: "warning",
};

function fmt(ts?: string): string {
  if (!ts) return "—";
  const d = new Date(ts);
  return Number.isNaN(d.getTime()) ? ts : d.toLocaleString();
}

export function CustomerDetailPage() {
  const { id } = useParams();
  const [sp] = useSearchParams();
  const tenantId = sp.get("tenantId") ?? "";
  const queryClient = useQueryClient();

  const customer = useQuery({
    queryKey: ["customer", id, tenantId],
    queryFn: () => api<Customer>(`/customers/${id}?tenantId=${tenantId}`),
  });
  const deps = useQuery({
    queryKey: ["deployments", id],
    queryFn: () => api<Deployment[]>(`/deployments/${id}`),
    refetchInterval: 10_000,
  });
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

  // Inline display-name editor state. Kept local because the edit is
  // ephemeral: on save we PATCH and invalidate the customer query so the
  // canonical value comes back from the server.
  const [editing, setEditing] = useState(false);
  const [draftName, setDraftName] = useState("");
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  function startEdit() {
    setDraftName(customer.data?.displayName ?? "");
    setSaveError(null);
    setEditing(true);
  }
  function cancelEdit() {
    setEditing(false);
    setSaveError(null);
  }
  async function saveEdit() {
    const name = draftName.trim();
    if (!name) {
      setSaveError("Display name is required.");
      return;
    }
    setSaving(true);
    setSaveError(null);
    try {
      await api<Customer>(
        `/customers/${id}?tenantId=${encodeURIComponent(tenantId)}`,
        {
          method: "PATCH",
          body: JSON.stringify({ displayName: name }),
        },
      );
      await queryClient.invalidateQueries({ queryKey: ["customer", id, tenantId] });
      setEditing(false);
    } catch (e) {
      setSaveError(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  }

  const prerequisites = customer.data?.prerequisites;
  const prerequisitesLink = `/customers/${id}/prerequisites?tenantId=${tenantId}`;
  const delegationOk = delegation.data?.ok === true;
  const canDeployScenario = delegationOk && !!prerequisites && prerequisites.status === "Succeeded";
  const canDeployPrereq = delegationOk;

  return (
    <div>
      {!editing && (
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <h1 style={{ margin: 0 }}>{customer.data?.displayName}</h1>
          {customer.data && (
            <Button
              size="small"
              appearance="subtle"
              onClick={startEdit}
              aria-label="Edit display name"
            >
              Edit
            </Button>
          )}
        </div>
      )}
      {editing && (
        <div style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
          <Input
            value={draftName}
            onChange={(_, d) => setDraftName(d.value)}
            disabled={saving}
            style={{ minWidth: 320 }}
            aria-label="Display name"
          />
          <Button appearance="primary" onClick={saveEdit} disabled={saving}>
            {saving ? "Saving…" : "Save"}
          </Button>
          <Button onClick={cancelEdit} disabled={saving}>
            Cancel
          </Button>
        </div>
      )}
      {saveError && (
        <p style={{ color: "#a4262c", margin: "4px 0" }}>
          <strong>Error:</strong> {saveError}
        </p>
      )}
      <p>
        <small>{customer.data?.subscriptionId}</small>
      </p>

      <div style={{ display: "flex", gap: 8, marginBottom: 16 }}>
        <Link to={`/customers/${id}/deploy?tenantId=${tenantId}`}>
          <Button appearance="primary" disabled={!canDeployScenario}>Deploy scenario</Button>
        </Link>
        <Link to={prerequisitesLink}>
          <Button disabled={!canDeployPrereq}>{prerequisites ? "Manage prerequisites" : "Deploy prerequisites"}</Button>
        </Link>
      </div>

      {delegation.data && !delegation.data.ok && (
        <MessageBar intent="error" style={{ marginBottom: 16 }}>
          <MessageBarBody>
            <MessageBarTitle>Delegation revoked or missing</MessageBarTitle>
            {delegation.data.message ??
              "The partner UAMI cannot read this subscription. Re-onboard the customer (Lighthouse offer) before deploying."}
          </MessageBarBody>
        </MessageBar>
      )}

      <h2 style={{ marginTop: 0 }}>Prerequisites</h2>
      {customer.isSuccess && !prerequisites && (
        <MessageBar intent="warning" style={{ marginBottom: 16 }}>
          <MessageBarBody>
            <MessageBarTitle>Prerequisites not deployed</MessageBarTitle>
            The customer subscription does not yet have the smb-rf management
            group, policies, or baseline. <Link to={prerequisitesLink}>Deploy them</Link>{" "}
            before running scenario deployments.
          </MessageBarBody>
        </MessageBar>
      )}
      {prerequisites && (
        <MessageBar
          intent={
            prerequisites.status === "Succeeded"
              ? "success"
              : prerequisites.status === "Failed"
                ? "error"
                : "info"
          }
          style={{ marginBottom: 16 }}
        >
          <MessageBarBody>
            <MessageBarTitle>Prerequisites {prerequisites.status.toLowerCase()}</MessageBarTitle>
            Template <code>{prerequisites.templateVersion}</code> &middot; deployed{" "}
            {fmt(prerequisites.deployedAt)} &middot;{" "}
            <Link to={prerequisitesLink}>Review or update</Link>
          </MessageBarBody>
        </MessageBar>
      )}

      <h2>Deployments</h2>
      {deps.data && deps.data.length === 0 && (
        <p style={{ color: "var(--text-muted)" }}>No deployments yet.</p>
      )}
      {deps.data && deps.data.length > 0 && (
        <Table size="small" aria-label="Deployments">
          <TableHeader>
            <TableRow>
              <TableHeaderCell>Environment</TableHeaderCell>
              <TableHeaderCell>Scenario</TableHeaderCell>
              <TableHeaderCell>Status</TableHeaderCell>
              <TableHeaderCell>Started</TableHeaderCell>
              <TableHeaderCell>Completed</TableHeaderCell>
            </TableRow>
          </TableHeader>
          <TableBody>
            {deps.data.map((d) => (
              <TableRow key={d.id}>
                <TableCell>
                  <Link to={`/customers/${id}/deployments/${d.id}`}>
                    {d.environmentName}
                  </Link>
                </TableCell>
                <TableCell>{d.scenario}</TableCell>
                <TableCell>
                  <Badge color={depColor[d.status]} appearance="filled">
                    {d.status}
                  </Badge>
                </TableCell>
                <TableCell>{fmt(d.startedAt ?? d.createdAt)}</TableCell>
                <TableCell>{fmt(d.completedAt)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </div>
  );
}
