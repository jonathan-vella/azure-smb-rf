// Internal feature flags. Values come from Vite env vars at build time
// (e.g. VITE_FEATURE_VPN=true). Treat any value other than the literal
// string "true" as disabled.
function flag(name: string): boolean {
  return (import.meta.env[name] as string | undefined) === "true";
}

export const featureFlags = {
  vpn: flag("VITE_FEATURE_VPN"),
};
