import { useMemo, useState } from "react";
import { useParams, useSearchParams, Link, Navigate } from "react-router-dom";
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
  Tag,
  TagGroup,
  Dialog,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  DialogTrigger,
  DialogActions,
} from "@fluentui/react-components";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "../api";

interface DeploymentRow {
  id: string;
  environmentName: string;
  scenario: string;
  status: string;
  parameters?: Record<string, string>;
  createdAt?: string;
  completedAt?: string | null;
}

interface IpsecPolicy {
  ikeEncryption: string;
  ikeIntegrity: string;
  dhGroup: string;
  ikeLifetimeSeconds: number;
  ipsecEncryption: string;
  ipsecIntegrity: string;
  pfsGroup: string;
  ipsecLifetimeSeconds: number;
}

interface VpnStatus {
  gatewayPublicIp: string | null;
  gatewayResourceId: string;
  localNetworkGatewayName: string;
  localNetworkGatewayResourceId: string;
  currentOnPremGatewayIp: string | null;
  currentOnPremCidrs: string[];
  hasPlaceholderAddresses: boolean;
  hasPsk: boolean;
  connectionName: string | null;
  connectionResourceId: string | null;
  connectionStatus: string | null;
  currentIpsecPolicy: IpsecPolicy | null;
}

const DEFAULT_IPSEC: IpsecPolicy = {
  ikeEncryption: "AES256",
  ikeIntegrity: "SHA256",
  dhGroup: "DHGroup14",
  ikeLifetimeSeconds: 28800,
  ipsecEncryption: "AES256",
  ipsecIntegrity: "SHA256",
  pfsGroup: "PFS14",
  ipsecLifetimeSeconds: 27000,
};

const IKE_ENC = ["AES256", "AES192", "AES128", "GCMAES256", "GCMAES128"];
const IKE_INT = ["SHA256", "SHA384", "SHA1", "MD5"];
const DH_GROUPS = [
  "DHGroup14",
  "DHGroup24",
  "ECP256",
  "ECP384",
  "DHGroup2",
  "DHGroup2048",
];
const IPSEC_ENC = [
  "AES256",
  "AES192",
  "AES128",
  "GCMAES256",
  "GCMAES192",
  "GCMAES128",
  "DES",
  "DES3",
  "None",
];
const IPSEC_INT = [
  "SHA256",
  "GCMAES256",
  "GCMAES192",
  "GCMAES128",
  "SHA1",
  "MD5",
];
const PFS = [
  "PFS14",
  "PFS24",
  "PFS2",
  "PFS2048",
  "ECP256",
  "ECP384",
  "PFSMM",
  "None",
];

function splitCidrs(value: string | undefined | null): string[] {
  if (!value) return [];
  return value
    .split(/[\s,]+/)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

export function VpnPage() {
  const { id } = useParams();
  const [sp] = useSearchParams();
  const tenantId = sp.get("tenantId") ?? "";
  const envName = sp.get("env") ?? "";
  const qc = useQueryClient();

  // Resolve the deployment to prefill from. We refetch every 10s so that
  // mid-rotation status changes (e.g. connection coming up) are reflected.
  const deps = useQuery({
    queryKey: ["deployments", id],
    queryFn: () =>
      api<DeploymentRow[]>(
        `/deployments/${id}?tenantId=${encodeURIComponent(tenantId)}`,
      ),
    enabled: !!id && !!tenantId,
  });

  const lastVpnDeployment = useMemo(() => {
    const list = deps.data ?? [];
    const matches = list.filter(
      (d) =>
        d.status === "Succeeded" &&
        (d.scenario === "Vpn" || d.scenario === "Full") &&
        (envName ? d.environmentName === envName : true),
    );
    matches.sort((a, b) =>
      (b.completedAt ?? b.createdAt ?? "").localeCompare(
        a.completedAt ?? a.createdAt ?? "",
      ),
    );
    return matches[0];
  }, [deps.data, envName]);

  const effectiveEnv = envName || lastVpnDeployment?.environmentName || "";

  const status = useQuery({
    queryKey: ["vpn-status", id, effectiveEnv],
    queryFn: () =>
      api<VpnStatus>(
        `/vpn/${id}/${effectiveEnv}?tenantId=${encodeURIComponent(tenantId)}`,
      ),
    enabled: !!id && !!tenantId && !!effectiveEnv,
    refetchInterval: 10_000,
  });

  // Form state. Prefill order: live status → last deployment params →
  // sensible defaults. We don't reset on every render because the user is
  // mid-edit; only seed on first arrival via a derived initial value.
  const seed = useMemo(() => {
    const params = lastVpnDeployment?.parameters ?? {};
    const peerIp =
      status.data?.currentOnPremGatewayIp ??
      params["ON_PREMISES_GATEWAY_PUBLIC_IP"] ??
      "";
    const cidrs =
      status.data && status.data.currentOnPremCidrs.length > 0
        ? status.data.currentOnPremCidrs
        : splitCidrs(params["ON_PREMISES_ADDRESS_SPACE"]);
    const ipsec = status.data?.currentIpsecPolicy ?? DEFAULT_IPSEC;
    return { peerIp, cidrs, ipsec };
  }, [status.data, lastVpnDeployment]);

  const [peerIp, setPeerIp] = useState<string | null>(null);
  const [cidrInput, setCidrInput] = useState<string>("");
  const [cidrs, setCidrs] = useState<string[] | null>(null);
  const [ipsec, setIpsec] = useState<IpsecPolicy | null>(null);

  const effectivePeerIp = peerIp ?? seed.peerIp;
  const effectiveCidrs = cidrs ?? seed.cidrs;
  const effectiveIpsec = ipsec ?? seed.ipsec;

  function patchIpsec<K extends keyof IpsecPolicy>(
    key: K,
    value: IpsecPolicy[K],
  ) {
    setIpsec({ ...effectiveIpsec, [key]: value });
  }
  function addCidr() {
    const trimmed = cidrInput.trim();
    if (!trimmed) return;
    if (effectiveCidrs.includes(trimmed)) {
      setCidrInput("");
      return;
    }
    setCidrs([...effectiveCidrs, trimmed]);
    setCidrInput("");
  }
  function removeCidr(value: string) {
    setCidrs(effectiveCidrs.filter((c) => c !== value));
  }

  const [pskModal, setPskModal] = useState<string | null>(null);
  const [confirmRotate, setConfirmRotate] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);

  const rotate = useMutation({
    mutationFn: () =>
      api<{ psk: string }>(
        `/vpn/${id}/${effectiveEnv}/psk?tenantId=${encodeURIComponent(tenantId)}`,
        { method: "POST" },
      ),
    onSuccess: (data) => {
      setPskModal(data.psk);
      setConfirmRotate(false);
      qc.invalidateQueries({ queryKey: ["vpn-status", id, effectiveEnv] });
    },
  });

  const connect = useMutation({
    mutationFn: () =>
      api<{ pskRotated: boolean; plaintextPskOnce: string | null }>(
        `/vpn/${id}/${effectiveEnv}/connect?tenantId=${encodeURIComponent(tenantId)}`,
        {
          method: "POST",
          body: JSON.stringify({
            onPremGatewayIp: effectivePeerIp,
            onPremCidrs: effectiveCidrs,
            ipsec: effectiveIpsec,
            rotatePsk: false,
          }),
        },
      ),
    onSuccess: (data) => {
      if (data.plaintextPskOnce) setPskModal(data.plaintextPskOnce);
      qc.invalidateQueries({ queryKey: ["vpn-status", id, effectiveEnv] });
    },
  });

  const drop = useMutation({
    mutationFn: () =>
      api<void>(
        `/vpn/${id}/${effectiveEnv}/connection?tenantId=${encodeURIComponent(tenantId)}`,
        { method: "DELETE" },
      ),
    onSuccess: () => {
      setConfirmDelete(false);
      qc.invalidateQueries({ queryKey: ["vpn-status", id, effectiveEnv] });
    },
  });

  if (!id || !tenantId) {
    return <p>Missing customer id or tenantId.</p>;
  }
  if (deps.isSuccess && !lastVpnDeployment) {
    return (
      <Navigate
        to={`/customers/${id}?tenantId=${encodeURIComponent(tenantId)}`}
        replace
      />
    );
  }

  return (
    <div>
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <h1 style={{ margin: 0 }}>VPN configuration</h1>
        {effectiveEnv && (
          <Tag appearance="outline" size="small">
            {effectiveEnv}
          </Tag>
        )}
      </div>
      <p>
        <Link to={`/customers/${id}?tenantId=${encodeURIComponent(tenantId)}`}>
          ← Back to customer
        </Link>
      </p>

      {status.isLoading && <Spinner label="Loading VPN status…" />}
      {status.error && (
        <MessageBar intent="error">
          <MessageBarBody>
            <MessageBarTitle>Failed to load VPN status</MessageBarTitle>
            {String((status.error as Error).message)}
          </MessageBarBody>
        </MessageBar>
      )}

      {status.data && (
        <>
          <section style={{ marginBottom: 24 }}>
            <h2>Azure side</h2>
            <p>
              <strong>Gateway public IP:</strong>{" "}
              <code>{status.data.gatewayPublicIp ?? "unknown"}</code>{" "}
              {status.data.gatewayPublicIp && (
                <Button
                  size="small"
                  appearance="subtle"
                  onClick={() =>
                    navigator.clipboard.writeText(status.data!.gatewayPublicIp!)
                  }
                >
                  Copy
                </Button>
              )}
            </p>
            <p>
              <strong>Connection status:</strong>{" "}
              <Tag
                appearance={
                  status.data.connectionStatus === "Connected"
                    ? "filled"
                    : "outline"
                }
                size="small"
              >
                {status.data.connectionStatus ?? "Not configured"}
              </Tag>
            </p>
            <p>
              <strong>PSK:</strong>{" "}
              {status.data.hasPsk ? "Stored in Key Vault" : "Not set"}{" "}
              <Button
                size="small"
                onClick={() => setConfirmRotate(true)}
                disabled={rotate.isPending}
              >
                Rotate PSK
              </Button>
            </p>
            {status.data.hasPlaceholderAddresses && (
              <MessageBar intent="warning">
                <MessageBarBody>
                  <MessageBarTitle>Placeholder values detected</MessageBarTitle>
                  The Local Network Gateway still has the foundation's RFC 5737
                  placeholder address. Save the form below to write the real
                  on-prem peer IP and CIDRs.
                </MessageBarBody>
              </MessageBar>
            )}
          </section>

          <section style={{ marginBottom: 24 }}>
            <h2>On-premises side</h2>
            <Field label="Peer (on-prem) public IP">
              <Input
                value={effectivePeerIp}
                onChange={(_, d) => setPeerIp(d.value)}
                placeholder="203.0.113.1"
              />
            </Field>
            <Field
              label="On-prem address spaces (CIDR)"
              hint="Press Enter or comma to add."
            >
              <Input
                value={cidrInput}
                onChange={(_, d) => setCidrInput(d.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === ",") {
                    e.preventDefault();
                    addCidr();
                  }
                }}
                placeholder="10.50.0.0/16"
              />
            </Field>
            {effectiveCidrs.length > 0 && (
              <TagGroup
                onDismiss={(_, d) => removeCidr(String(d.value))}
                style={{ marginTop: 8 }}
              >
                {effectiveCidrs.map((c) => (
                  <Tag key={c} value={c} dismissible>
                    {c}
                  </Tag>
                ))}
              </TagGroup>
            )}
          </section>

          <section style={{ marginBottom: 24 }}>
            <h2>IPsec policy</h2>
            <div
              style={{
                display: "grid",
                gridTemplateColumns: "1fr 1fr",
                gap: 12,
              }}
            >
              <Field label="IKE encryption">
                <Dropdown
                  value={effectiveIpsec.ikeEncryption}
                  selectedOptions={[effectiveIpsec.ikeEncryption]}
                  onOptionSelect={(_, d) =>
                    patchIpsec("ikeEncryption", d.optionValue ?? "")
                  }
                >
                  {IKE_ENC.map((v) => (
                    <Option key={v} value={v}>
                      {v}
                    </Option>
                  ))}
                </Dropdown>
              </Field>
              <Field label="IKE integrity">
                <Dropdown
                  value={effectiveIpsec.ikeIntegrity}
                  selectedOptions={[effectiveIpsec.ikeIntegrity]}
                  onOptionSelect={(_, d) =>
                    patchIpsec("ikeIntegrity", d.optionValue ?? "")
                  }
                >
                  {IKE_INT.map((v) => (
                    <Option key={v} value={v}>
                      {v}
                    </Option>
                  ))}
                </Dropdown>
              </Field>
              <Field label="DH group">
                <Dropdown
                  value={effectiveIpsec.dhGroup}
                  selectedOptions={[effectiveIpsec.dhGroup]}
                  onOptionSelect={(_, d) =>
                    patchIpsec("dhGroup", d.optionValue ?? "")
                  }
                >
                  {DH_GROUPS.map((v) => (
                    <Option key={v} value={v}>
                      {v}
                    </Option>
                  ))}
                </Dropdown>
              </Field>
              <Field label="IKE SA lifetime (sec)">
                <Input
                  type="number"
                  value={String(effectiveIpsec.ikeLifetimeSeconds)}
                  onChange={(_, d) =>
                    patchIpsec("ikeLifetimeSeconds", Number(d.value) || 0)
                  }
                />
              </Field>
              <Field label="IPsec encryption">
                <Dropdown
                  value={effectiveIpsec.ipsecEncryption}
                  selectedOptions={[effectiveIpsec.ipsecEncryption]}
                  onOptionSelect={(_, d) =>
                    patchIpsec("ipsecEncryption", d.optionValue ?? "")
                  }
                >
                  {IPSEC_ENC.map((v) => (
                    <Option key={v} value={v}>
                      {v}
                    </Option>
                  ))}
                </Dropdown>
              </Field>
              <Field label="IPsec integrity">
                <Dropdown
                  value={effectiveIpsec.ipsecIntegrity}
                  selectedOptions={[effectiveIpsec.ipsecIntegrity]}
                  onOptionSelect={(_, d) =>
                    patchIpsec("ipsecIntegrity", d.optionValue ?? "")
                  }
                >
                  {IPSEC_INT.map((v) => (
                    <Option key={v} value={v}>
                      {v}
                    </Option>
                  ))}
                </Dropdown>
              </Field>
              <Field label="PFS group">
                <Dropdown
                  value={effectiveIpsec.pfsGroup}
                  selectedOptions={[effectiveIpsec.pfsGroup]}
                  onOptionSelect={(_, d) =>
                    patchIpsec("pfsGroup", d.optionValue ?? "")
                  }
                >
                  {PFS.map((v) => (
                    <Option key={v} value={v}>
                      {v}
                    </Option>
                  ))}
                </Dropdown>
              </Field>
              <Field label="IPsec SA lifetime (sec)">
                <Input
                  type="number"
                  value={String(effectiveIpsec.ipsecLifetimeSeconds)}
                  onChange={(_, d) =>
                    patchIpsec("ipsecLifetimeSeconds", Number(d.value) || 0)
                  }
                />
              </Field>
            </div>
          </section>

          <div style={{ display: "flex", gap: 8 }}>
            <Button
              appearance="primary"
              onClick={() => connect.mutate()}
              disabled={
                connect.isPending ||
                !effectivePeerIp ||
                effectiveCidrs.length === 0
              }
            >
              {connect.isPending ? "Saving…" : "Save connection"}
            </Button>
            <Button
              appearance="secondary"
              onClick={() => setConfirmDelete(true)}
              disabled={!status.data.connectionResourceId || drop.isPending}
            >
              Delete connection
            </Button>
          </div>

          {connect.error && (
            <MessageBar intent="error" style={{ marginTop: 12 }}>
              <MessageBarBody>
                <MessageBarTitle>Save failed</MessageBarTitle>
                {String((connect.error as Error).message)}
              </MessageBarBody>
            </MessageBar>
          )}
        </>
      )}

      {/* PSK reveal modal — shown ONCE after rotation. The plaintext is not
          persisted in component state across navigations. */}
      <Dialog
        open={!!pskModal}
        onOpenChange={(_, d) => !d.open && setPskModal(null)}
      >
        <DialogSurface>
          <DialogBody>
            <DialogTitle>Pre-shared key (one-time view)</DialogTitle>
            <DialogContent>
              <p>
                Copy this PSK to your on-prem VPN device now. After closing this
                dialog the value cannot be retrieved again — you'll need to
                rotate to issue a new one.
              </p>
              <Input value={pskModal ?? ""} readOnly />
              <Button
                style={{ marginTop: 8 }}
                onClick={() =>
                  pskModal && navigator.clipboard.writeText(pskModal)
                }
              >
                Copy PSK
              </Button>
            </DialogContent>
            <DialogActions>
              <DialogTrigger disableButtonEnhancement>
                <Button appearance="primary">I've copied it</Button>
              </DialogTrigger>
            </DialogActions>
          </DialogBody>
        </DialogSurface>
      </Dialog>

      {/* Rotate confirmation. Rotating the PSK does NOT push it to Azure
          until the user clicks Save connection — but if there's already a
          connection in place, traffic will drop until both sides match. */}
      <Dialog
        open={confirmRotate}
        onOpenChange={(_, d) => setConfirmRotate(d.open)}
      >
        <DialogSurface>
          <DialogBody>
            <DialogTitle>Rotate pre-shared key?</DialogTitle>
            <DialogContent>
              A new PSK will be generated and stored. Tunnel traffic will fail
              until you also configure the new PSK on the on-prem device.
            </DialogContent>
            <DialogActions>
              <Button onClick={() => setConfirmRotate(false)}>Cancel</Button>
              <Button
                appearance="primary"
                onClick={() => rotate.mutate()}
                disabled={rotate.isPending}
              >
                Rotate
              </Button>
            </DialogActions>
          </DialogBody>
        </DialogSurface>
      </Dialog>

      <Dialog
        open={confirmDelete}
        onOpenChange={(_, d) => setConfirmDelete(d.open)}
      >
        <DialogSurface>
          <DialogBody>
            <DialogTitle>Delete VPN connection?</DialogTitle>
            <DialogContent>
              The IPsec connection resource will be removed. The Local Network
              Gateway and PSK are kept so you can recreate the connection later.
            </DialogContent>
            <DialogActions>
              <Button onClick={() => setConfirmDelete(false)}>Cancel</Button>
              <Button
                appearance="primary"
                onClick={() => drop.mutate()}
                disabled={drop.isPending}
              >
                Delete
              </Button>
            </DialogActions>
          </DialogBody>
        </DialogSurface>
      </Dialog>
    </div>
  );
}
