// Reusable region picker. Always shows the LIVE list of regions for a given
// subscription via the API's `/locations?subscriptionId=...` endpoint, which
// fans out to ARM using the partner UAMI (so the SPA never needs an
// interactive ARM token in the customer tenant).
//
// The input itself is a pure search field (filter only). Selected regions
// are rendered as chips above the input so typing always filters the list
// instead of fighting an existing summary value.
import { useMemo, useState } from "react";
import {
  Combobox,
  Option,
  Spinner,
  Tag,
  TagGroup,
} from "@fluentui/react-components";
import { useQuery } from "@tanstack/react-query";
import { api } from "./api";
import { REGION_LABELS } from "./regions";

export interface RegionOption {
  id: string;
  label: string;
}

interface ApiLocation {
  id: string;
  displayName: string;
}

export function useAzureLocations(subscriptionId: string | undefined) {
  // When no subscriptionId is supplied the API falls back to the partner's
  // own management subscription. This is the right default for onboarding
  // flows that run before a Lighthouse delegation is in place.
  const query = useQuery<RegionOption[]>({
    queryKey: ["azure-locations", subscriptionId ?? "__partner__"],
    staleTime: 30 * 60 * 1000,
    gcTime: 60 * 60 * 1000,
    retry: false,
    queryFn: async () => {
      const qs = subscriptionId
        ? `?subscriptionId=${encodeURIComponent(subscriptionId)}`
        : "";
      const list = await api<ApiLocation[]>(`/locations${qs}`);
      return list.map((l) => ({
        id: l.id,
        label: l.displayName || REGION_LABELS[l.id] || l.id,
      }));
    },
  });

  return {
    options: query.data ?? [],
    isLoading: query.isLoading,
    isError: query.isError,
    error: query.error as Error | null,
  };
}

interface BasePickerProps {
  /** Subscription whose region list to load via the partner UAMI. */
  subscriptionId?: string;
  disabled?: boolean;
  placeholder?: string;
  /** Restrict the picker to this allow-list (used by DeployPage). */
  allowedIds?: string[];
}

interface SingleProps extends BasePickerProps {
  value: string;
  onChange: (id: string) => void;
}

interface MultiProps extends BasePickerProps {
  values: string[];
  onChange: (ids: string[]) => void;
}

function StatusLine({
  loading,
  isError,
  error,
}: {
  loading: boolean;
  isError: boolean;
  error: Error | null;
}) {
  if (loading) {
    return (
      <span style={{ fontSize: "0.8rem" }}>
        <Spinner size="tiny" /> loading regions…
      </span>
    );
  }
  if (isError) {
    return (
      <span style={{ fontSize: "0.8rem", color: "crimson" }}>
        Could not load regions: {error?.message ?? "unknown error"}.
      </span>
    );
  }
  return null;
}

export function RegionPicker(props: SingleProps) {
  const { options, isLoading, isError, error } = useAzureLocations(
    props.subscriptionId,
  );
  const [filter, setFilter] = useState("");

  const visible = useMemo(() => {
    let list = options;
    if (props.allowedIds && props.allowedIds.length > 0) {
      const allow = new Set(props.allowedIds);
      list = list.filter((o) => allow.has(o.id));
    }
    const q = filter.trim().toLowerCase();
    if (!q) return list;
    return list.filter(
      (o) =>
        o.id.toLowerCase().includes(q) || o.label.toLowerCase().includes(q),
    );
  }, [options, filter, props.allowedIds]);

  const selectedLabel =
    options.find((o) => o.id === props.value)?.label ??
    REGION_LABELS[props.value] ??
    props.value ??
    "";

  return (
    <>
      <Combobox
        freeform
        placeholder={
          props.placeholder ??
          (selectedLabel
            ? `Selected: ${selectedLabel}`
            : "Type to search regions…")
        }
        disabled={props.disabled}
        // Bind the textbox to the live search filter only. The current
        // selection is shown via `selectedOptions` (highlighted in the
        // dropdown) and via the placeholder; displaying it in the input
        // itself fights the search experience.
        value={filter}
        selectedOptions={props.value ? [props.value] : []}
        onInput={(e) => setFilter((e.target as HTMLInputElement).value)}
        onOpenChange={(_, d) => {
          if (!d.open) setFilter("");
        }}
        onOptionSelect={(_, d) => {
          if (d.optionValue) {
            props.onChange(d.optionValue);
            setFilter("");
          }
        }}
      >
        {visible.map((r) => (
          <Option key={r.id} value={r.id} text={r.label}>
            {r.label}
          </Option>
        ))}
        {visible.length === 0 && (
          <Option key="__empty" value="" disabled text="No matches">
            No matches
          </Option>
        )}
      </Combobox>
      <div style={{ marginTop: 4 }}>
        <StatusLine
          loading={isLoading}
          isError={isError}
          error={error}
        />
      </div>
    </>
  );
}

export function RegionMultiPicker(props: MultiProps) {
  const { options, isLoading, isError, error } = useAzureLocations(
    props.subscriptionId,
  );
  const [filter, setFilter] = useState("");

  const visible = useMemo(() => {
    const q = filter.trim().toLowerCase();
    if (!q) return options;
    return options.filter(
      (o) =>
        o.id.toLowerCase().includes(q) || o.label.toLowerCase().includes(q),
    );
  }, [options, filter]);

  const labelFor = (id: string) =>
    options.find((o) => o.id === id)?.label ?? REGION_LABELS[id] ?? id;

  const removeOne = (id: string) =>
    props.onChange(props.values.filter((v) => v !== id));

  return (
    <>
      {props.values.length > 0 && (
        <TagGroup
          aria-label="Selected regions"
          onDismiss={(_, d) =>
            typeof d.value === "string" ? removeOne(d.value) : undefined
          }
          style={{ marginBottom: 6, flexWrap: "wrap" }}
        >
          {props.values.map((id) => (
            <Tag key={id} value={id} dismissible shape="rounded">
              {labelFor(id)}
            </Tag>
          ))}
        </TagGroup>
      )}
      <Combobox
        multiselect
        freeform
        placeholder={
          props.placeholder ??
          (props.values.length
            ? "Type to add another region…"
            : "Type to search regions…")
        }
        disabled={props.disabled}
        // Pure search field. Selected values are rendered as chips above.
        value={filter}
        selectedOptions={props.values}
        onInput={(e) => setFilter((e.target as HTMLInputElement).value)}
        onOpenChange={(_, d) => {
          if (!d.open) setFilter("");
        }}
        onOptionSelect={(_, d) => {
          props.onChange(d.selectedOptions);
          setFilter("");
        }}
      >
        {visible.map((r) => (
          <Option key={r.id} value={r.id} text={r.label}>
            {r.label}
          </Option>
        ))}
        {visible.length === 0 && (
          <Option key="__empty" value="" disabled text="No matches">
            No matches
          </Option>
        )}
      </Combobox>
      <div style={{ marginTop: 4 }}>
        <StatusLine
          loading={isLoading}
          isError={isError}
          error={error}
        />
      </div>
    </>
  );
}
