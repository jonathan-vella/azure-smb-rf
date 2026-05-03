import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Link, useNavigate } from "react-router-dom";
import {
  Badge,
  Button,
  Dialog,
  DialogTrigger,
  DialogSurface,
  DialogTitle,
  DialogBody,
  DialogActions,
  DialogContent,
  Toolbar,
  ToolbarButton,
  ToolbarDivider,
} from "@fluentui/react-components";
import {
  AddRegular,
  DeleteRegular,
  InfoRegular,
  RocketRegular,
} from "@fluentui/react-icons";
import { api } from "../api";

interface Customer {
  id: string;
  displayName: string;
  subscriptionId: string;
  tenantId: string;
}

interface CustomerListItem {
  customer: Customer;
  delegationStatus: "active" | "revoked" | "unknown" | "unchecked";
}

function StatusBadge({ status }: { status: CustomerListItem["delegationStatus"] }) {
  if (status === "active") {
    return <Badge color="success" appearance="tint">Lighthouse OK</Badge>;
  }
  // "revoked" / "unknown" / "unchecked" — the list no longer probes ARM, so
  // we just don't show a badge. Delegation is verified on the Deploy page.
  return null;
}

export function CustomersPage() {
  const qc = useQueryClient();
  const navigate = useNavigate();
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);

  const q = useQuery({
    queryKey: ["customers"],
    queryFn: () => api<CustomerListItem[]>("/customers"),
    refetchInterval: 60_000,
  });

  const selected = q.data?.find((x) => x.customer.id === selectedId) ?? null;
  const hasSelection = selected !== null;
  const deployDisabled = !selected;

  async function handleDelete() {
    if (!selected) return;
    setDeleting(true);
    setDeleteError(null);
    try {
      await api(`/customers/${selected.customer.id}?tenantId=${selected.customer.tenantId}`, {
        method: "DELETE",
      });
      setSelectedId(null);
      setDeleteDialogOpen(false);
      await qc.invalidateQueries({ queryKey: ["customers"] });
    } catch (e) {
      setDeleteError((e as Error).message);
    } finally {
      setDeleting(false);
    }
  }

  return (
    <div>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          marginBottom: 8,
        }}
      >
        <h1 style={{ margin: 0 }}>Customers</h1>
      </div>
      <p style={{ color: "var(--text-muted)", marginTop: 0 }}>
        Customers delegated via Azure Lighthouse to this partner tenant.
      </p>

      {/* Toolbar — operates on the selected customer (single-select). */}
      <Toolbar
        aria-label="Customer actions"
        size="medium"
        style={{
          background: "var(--toolbar-bg, rgba(127,127,127,0.08))",
          border: "1px solid var(--border)",
          borderRadius: 6,
          padding: "4px 8px",
          marginBottom: 12,
          gap: 4,
        }}
      >
        <ToolbarButton
          icon={<AddRegular />}
          appearance="primary"
          onClick={() => navigate("/customers/onboard")}
        >
          Onboard
        </ToolbarButton>

        <ToolbarDivider />

        <ToolbarButton
          icon={<InfoRegular />}
          appearance="subtle"
          disabled={!hasSelection}
          onClick={() =>
            selected &&
            navigate(`/customers/${selected.customer.id}?tenantId=${selected.customer.tenantId}`)
          }
        >
          Details
        </ToolbarButton>
        <ToolbarButton
          icon={<RocketRegular />}
          appearance="subtle"
          disabled={deployDisabled}
          onClick={() =>
            selected &&
            navigate(
              `/customers/${selected.customer.id}/deploy?tenantId=${selected.customer.tenantId}`
            )
          }
        >
          Deploy
        </ToolbarButton>

        <ToolbarDivider />

        <Dialog
          open={deleteDialogOpen}
          onOpenChange={(_, data) => {
            if (deleting) return;
            setDeleteDialogOpen(data.open);
            if (data.open) setDeleteError(null);
          }}
        >
          <DialogTrigger disableButtonEnhancement>
            <ToolbarButton icon={<DeleteRegular />} appearance="subtle" disabled={!hasSelection}>
              Delete
            </ToolbarButton>
          </DialogTrigger>
          <DialogSurface>
            <DialogBody>
              <DialogTitle>Delete customer</DialogTitle>
              <DialogContent>
                <p>
                  Remove <strong>{selected?.customer.displayName}</strong> (subscription{" "}
                  <code>{selected?.customer.subscriptionId}</code>) from the management console?
                </p>
                <p style={{ color: "var(--text-muted)" }}>
                  This only deletes the row from our Cosmos database. The Lighthouse delegation,
                  any deployed prerequisites, and customer-side resources are <strong>not</strong>{" "}
                  touched. You can re-onboard the same subscription afterwards.
                </p>
                {deleteError && (
                  <p style={{ color: "crimson" }}>Delete failed: {deleteError}</p>
                )}
              </DialogContent>
              <DialogActions>
                <DialogTrigger disableButtonEnhancement>
                  <Button appearance="secondary" disabled={deleting}>
                    Cancel
                  </Button>
                </DialogTrigger>
                <Button
                  appearance="primary"
                  disabled={deleting}
                  onClick={handleDelete}
                >
                  {deleting ? "Deleting…" : "Delete"}
                </Button>
              </DialogActions>
            </DialogBody>
          </DialogSurface>
        </Dialog>
      </Toolbar>

      {q.isLoading && <p>Loading…</p>}
      {q.isError && (
        <p style={{ color: "crimson" }}>Failed to load: {(q.error as Error).message}</p>
      )}
      {q.data && q.data.length === 0 && (
        <p>
          No customers yet. <Link to="/customers/onboard">Onboard your first customer</Link>.
        </p>
      )}

      <ul style={{ listStyle: "none", padding: 0, margin: 0 }}>
        {q.data?.map(({ customer: c, delegationStatus }) => {
          const isSelected = selectedId === c.id;
          return (
            <li
              key={c.id}
              className="list-row"
              onClick={() => setSelectedId(isSelected ? null : c.id)}
              style={{
                opacity: 1,
                cursor: "pointer",
                outline: isSelected ? "2px solid var(--accent, #2899f5)" : "none",
                outlineOffset: -2,
                background: isSelected ? "var(--row-selected, rgba(40,153,245,0.08))" : undefined,
              }}
            >
              <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                <input
                  type="radio"
                  name="customer-select"
                  checked={isSelected}
                  onChange={() => setSelectedId(c.id)}
                  onClick={(e) => e.stopPropagation()}
                  aria-label={`Select ${c.displayName}`}
                />
                <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                    <span style={{ fontWeight: 600 }}>{c.displayName}</span>
                    <StatusBadge status={delegationStatus} />
                  </div>
                  <small
                    style={{ color: "var(--text-muted)", fontFamily: "var(--font-mono)" }}
                  >
                    {c.subscriptionId}
                  </small>
                </div>
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
