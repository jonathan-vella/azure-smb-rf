import { useEffect, useRef, useState } from "react";
import { useParams } from "react-router-dom";
import { Badge, Button } from "@fluentui/react-components";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "../api";

interface Deployment {
  id: string;
  customerId: string;
  environmentName: string;
  status: "Queued" | "Running" | "Succeeded" | "Failed" | "Cancelled";
  jobExecutionName?: string;
  failureReason?: string;
  createdAt: string;
  startedAt?: string;
  completedAt?: string;
}

interface CustomerListItem {
  customer: { id: string; displayName: string; subscriptionId: string; tenantId: string };
  delegationStatus: string;
}

interface LogPage {
  lines: string[];
  nextLine: number;
}

const statusColor: Record<Deployment["status"], "informative" | "success" | "danger" | "warning"> = {
  Queued: "informative",
  Running: "informative",
  Succeeded: "success",
  Failed: "danger",
  Cancelled: "warning",
};

export function DeploymentDetailPage() {
  const { id, depId } = useParams();
  const qc = useQueryClient();
  const [cancelling, setCancelling] = useState(false);
  const [cancelError, setCancelError] = useState<string | null>(null);
  const ref = useRef<HTMLPreElement>(null);

  // Accumulated log lines + monotonic cursor. Reset when navigating between
  // different deployments (see effect below).
  const [lines, setLines] = useState<string[]>([]);
  const cursorRef = useRef(0);

  const dep = useQuery({
    queryKey: ["deployment", id, depId],
    queryFn: () => api<Deployment>(`/deployments/${id}/${depId}`),
    refetchInterval: 5_000,
    enabled: !!id && !!depId,
  });

  const customers = useQuery({
    queryKey: ["customers"],
    queryFn: () => api<CustomerListItem[]>("/customers"),
    staleTime: 60_000,
  });
  const customerName = customers.data?.find((c) => c.customer.id === id)?.customer.displayName;

  const status = dep.data?.status;
  const inFlight = status === "Queued" || status === "Running";

  // Reset accumulated log state when navigating between deployments so the
  // next page doesn't inherit the previous one's lines/cursor.
  useEffect(() => {
    setLines([]);
    cursorRef.current = 0;
  }, [id, depId]);

  // Cursor-based log polling. The blob is canonical and append-only, so we
  // can ask the API "give me everything after line N" and the next call
  // advances the cursor to wherever the worker has written by then. This
  // survives tab-away, refresh, and worker replica changes for free.
  //
  // While the deployment is in-flight we poll every 5s. Once it finishes
  // we do one final poll (since the worker may have flushed a last batch
  // *after* posting the terminal status) and then stop.
  useEffect(() => {
    if (!id || !depId) return;
    let cancelled = false;
    let timer: ReturnType<typeof setTimeout> | null = null;

    async function fetchOnce() {
      const page = await api<LogPage>(
        `/deployments/${id}/${depId}/logs?fromLine=${cursorRef.current}`,
      );
      if (cancelled) return;
      if (page.lines.length > 0) {
        setLines((prev) => prev.concat(page.lines));
      }
      cursorRef.current = page.nextLine;
    }

    async function loop() {
      if (cancelled) return;
      try { await fetchOnce(); } catch { /* transient: retry on next tick */ }
      if (cancelled) return;
      if (inFlight) {
        timer = setTimeout(loop, 5_000);
      }
    }

    void loop();

    // When the deployment transitions to a terminal status, do one extra
    // fetch ~2s later to capture any final lines the worker wrote between
    // its last log POST and its status POST.
    let trailingTimer: ReturnType<typeof setTimeout> | null = null;
    if (status && !inFlight) {
      trailingTimer = setTimeout(() => {
        fetchOnce().catch(() => { /* ignore */ });
      }, 2_000);
    }

    return () => {
      cancelled = true;
      if (timer) clearTimeout(timer);
      if (trailingTimer) clearTimeout(trailingTimer);
    };
  }, [id, depId, inFlight, status]);

  // Auto-scroll on new content.
  useEffect(() => {
    queueMicrotask(() => ref.current?.scrollTo(0, ref.current.scrollHeight));
  }, [lines.length]);

  async function cancel() {
    setCancelling(true);
    setCancelError(null);
    try {
      await api(`/deployments/${id}/${depId}/cancel`, { method: "POST" });
      await qc.invalidateQueries({ queryKey: ["deployment", id, depId] });
    } catch (e) {
      setCancelError((e as Error).message);
    } finally {
      setCancelling(false);
    }
  }

  return (
    <div>
      <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 4 }}>
        <h1 style={{ margin: 0 }}>Deployment {depId}</h1>
        {dep.data && (
          <Badge color={statusColor[dep.data.status]} appearance="filled">
            {dep.data.status}
          </Badge>
        )}
      </div>
      <p style={{ color: "var(--text-muted)", marginTop: 0 }}>
        Customer: {customerName ?? id}
        {dep.data?.environmentName && <> &middot; Env: {dep.data.environmentName}</>}
        {dep.data?.jobExecutionName && (
          <> &middot; Execution: <code>{dep.data.jobExecutionName}</code></>
        )}
      </p>

      <div style={{ display: "flex", gap: 8, marginBottom: 12 }}>
        <Button appearance="primary" disabled={!inFlight || cancelling} onClick={cancel}>
          {cancelling ? "Cancelling…" : "Cancel deployment"}
        </Button>
        {dep.data?.failureReason && (
          <span style={{ alignSelf: "center", color: "var(--text-muted)" }}>
            {dep.data.failureReason}
          </span>
        )}
        {cancelError && (
          <span style={{ alignSelf: "center", color: "crimson" }}>{cancelError}</span>
        )}
      </div>

      <pre
        ref={ref}
        style={{
          background: "#111",
          color: "#0f0",
          padding: 12,
          height: 480,
          overflow: "auto",
        }}
      >
        {lines.length === 0
          ? inFlight
            ? "Waiting for log stream…"
            : "No logs were captured for this deployment."
          : lines.join("\n")}
      </pre>
    </div>
  );
}
