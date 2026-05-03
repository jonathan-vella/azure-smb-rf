// Curated list of Azure regions partners typically deploy SMB foundations
// into. Shared between onboarding and the foundation edit page so both UIs
// show the same labels.
export const REGION_OPTIONS: Array<{ id: string; label: string }> = [
  { id: "swedencentral", label: "Sweden Central" },
  { id: "germanywestcentral", label: "Germany West Central" },
  { id: "westeurope", label: "West Europe" },
  { id: "northeurope", label: "North Europe" },
  { id: "francecentral", label: "France Central" },
  { id: "uksouth", label: "UK South" },
  { id: "ukwest", label: "UK West" },
  { id: "switzerlandnorth", label: "Switzerland North" },
  { id: "norwayeast", label: "Norway East" },
  { id: "italynorth", label: "Italy North" },
  { id: "polandcentral", label: "Poland Central" },
  { id: "spaincentral", label: "Spain Central" },
  { id: "eastus", label: "East US" },
  { id: "eastus2", label: "East US 2" },
  { id: "westus2", label: "West US 2" },
  { id: "westus3", label: "West US 3" },
  { id: "centralus", label: "Central US" },
  { id: "southcentralus", label: "South Central US" },
];

export const REGION_LABELS: Record<string, string> = REGION_OPTIONS.reduce(
  (acc, r) => {
    acc[r.id] = r.label;
    return acc;
  },
  {} as Record<string, string>,
);

// Normalises a partner-supplied region list the same way the API does: all
// lowercased, trimmed, deduped, 'global' force-included, ordinal-sorted.
export function normalizeAllowedRegions(
  regions: readonly string[],
  primary?: string,
): string[] {
  const merged = [...regions, ...(primary ? [primary] : []), "global"]
    .map((r) => r.trim().toLowerCase())
    .filter(Boolean);
  return Array.from(new Set(merged)).sort();
}