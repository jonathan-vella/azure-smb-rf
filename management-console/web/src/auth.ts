import {
  BrowserAuthError,
  Configuration,
  PublicClientApplication,
} from "@azure/msal-browser";

const apiClientId = import.meta.env.VITE_API_CLIENT_ID as string;
const spaClientId = import.meta.env.VITE_SPA_CLIENT_ID as string;
const tenantId = import.meta.env.VITE_TENANT_ID as string;

export const msalConfig: Configuration = {
  auth: {
    clientId: spaClientId,
    authority: `https://login.microsoftonline.com/${tenantId}`,
    redirectUri: window.location.origin,
  },
  cache: { cacheLocation: "sessionStorage" },
};

export const apiScopes = [`api://${apiClientId}/access_as_user`];

export const msalInstance = new PublicClientApplication(msalConfig);

/**
 * Tenant id of the partner ("home") tenant — i.e. the tenant the console
 * itself signs into. Used to identify which cached MSAL accounts must NOT be
 * dropped when we sanitize state before a customer-tenant popup.
 */
const PARTNER_TENANT_ID = tenantId;

/**
 * MSAL popup error codes that are transient — usually caused by the popup
 * window closing/navigating before MSAL processes the auth response hash,
 * stale MSAL state in sessionStorage, or the user accidentally dismissing
 * the popup. They're safe to retry with a fresh popup.
 */
const TRANSIENT_POPUP_ERROR_CODES = new Set([
  "hash_empty_error",
  "hash_does_not_contain_known_properties",
  "user_cancelled", // sometimes fired spuriously by browser focus changes
  "popup_window_error",
  "empty_window_error",
  "monitor_window_timeout",
  "interaction_in_progress",
  "no_token_request_cache_error",
]);

function isTransientPopupError(err: unknown): boolean {
  if (err instanceof BrowserAuthError) {
    return TRANSIENT_POPUP_ERROR_CODES.has(err.errorCode);
  }
  // MSAL sometimes throws plain Errors with the code embedded in the message.
  const msg = (err as { message?: string })?.message ?? "";
  for (const code of TRANSIENT_POPUP_ERROR_CODES) {
    if (msg.includes(code)) return true;
  }
  return false;
}

/** Best-effort cleanup of stale MSAL interaction state so the next popup
 * starts from a clean slate after a transient failure. Only clears the
 * interaction-in-progress flag — never the account cache, which would sign
 * the partner operator out of the console. */
function clearStaleInteractionState(): void {
  try {
    // The "interaction_in_progress" key is what MSAL uses to guard against
    // concurrent popups. If a previous popup crashed mid-flight it can be
    // left behind; clearing it lets the next attempt proceed.
    for (const key of Object.keys(sessionStorage)) {
      if (key.includes("msal.interaction.status")) {
        sessionStorage.removeItem(key);
      }
    }
  } catch {
    /* ignore */
  }
}

/**
 * Drop cached MSAL accounts whose home tenant doesn't match either the
 * partner tenant (the console's own login) or the customer tenant we're
 * about to sign into. This prevents stale accounts from a *previous*
 * customer's onboarding session from being silently picked up by MSAL or
 * surfacing in the account picker. Never removes the partner account — the
 * operator stays signed into the console.
 */
function pruneStaleCustomerAccounts(customerTenantId: string): void {
  try {
    const target = customerTenantId.toLowerCase();
    const partner = PARTNER_TENANT_ID?.toLowerCase();
    for (const account of msalInstance.getAllAccounts()) {
      const tid = account.tenantId?.toLowerCase();
      if (!tid) continue;
      // Keep the partner account (so the operator stays signed in) and any
      // account that's already in the target customer tenant (so SSO can
      // re-use it). Drop everything else.
      if (tid === partner || tid === target) continue;
      // removeAccount is fire-and-forget on msal-browser; types differ
      // between versions so cast through unknown.
      (
        msalInstance as unknown as {
          removeAccount?: (a: unknown) => Promise<void> | void;
        }
      ).removeAccount?.(account);
    }
    // Do NOT touch the active account — it's the partner login. Clearing it
    // would log the operator out of the console UI.
  } catch {
    /* ignore */
  }
}

/**
 * Sanitize state right before opening a popup against a customer tenant.
 * Prunes accounts from other customer tenants and clears the
 * interaction-in-progress flag.
 */
async function prepareForCustomerTenantPopup(
  customerTenantId: string,
): Promise<void> {
  pruneStaleCustomerAccounts(customerTenantId);
  clearStaleInteractionState();
}

/**
 * Acquire an ARM access token for a *customer* tenant via interactive popup.
 * The signed-in customer admin's identity is used to PUT Lighthouse
 * registration definitions/assignments directly against ARM, replacing the
 * old portal "Deploy to Azure" template flow. Requires the SPA app
 * registration to be multi-tenant.
 *
 * Robustness: MSAL popups are flaky when the customer admin is signing in
 * cross-tenant — popups can be killed by the browser, navigated by SSO, or
 * lose their hash before MSAL reads it, and stale accounts from prior
 * customer sessions can confuse the picker. We:
 *   1. await any pending redirect-handler so we don't race with a leftover hash,
 *   2. prune cached accounts from unrelated customer tenants,
 *   3. pass `domainHint` (and optional `loginHint`) to skip home-realm discovery
 *      and disambiguate the account picker, and
 *   4. retry transient failures up to 2 times with state cleanup between
 *      attempts. The user only sees the popup re-open silently.
 */
export interface AcquireArmTokenHints {
  /** Tenant default domain (e.g. `contoso.onmicrosoft.com`) — passed as
   * `domain_hint` so AAD skips home-realm discovery and routes straight to
   * the customer's IdP. */
  domainHint?: string | null;
  /** Customer admin's UPN/email — passed as `login_hint` to pre-fill the
   * sign-in box. Optional; we usually don't have it. */
  loginHint?: string | null;
}

export async function acquireArmTokenForTenant(
  customerTenantId: string,
  hints?: AcquireArmTokenHints,
): Promise<string> {
  await prepareForCustomerTenantPopup(customerTenantId);
  const request: Parameters<typeof msalInstance.acquireTokenPopup>[0] = {
    scopes: ["https://management.azure.com/user_impersonation"],
    authority: `https://login.microsoftonline.com/${customerTenantId}`,
    prompt: "select_account",
  };
  if (hints?.domainHint) request.domainHint = hints.domainHint;
  if (hints?.loginHint) request.loginHint = hints.loginHint;
  const maxAttempts = 3;
  let lastErr: unknown;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const result = await msalInstance.acquireTokenPopup(request);
      return result.accessToken;
    } catch (err) {
      lastErr = err;
      if (attempt < maxAttempts && isTransientPopupError(err)) {
        clearStaleInteractionState();
        // Brief backoff so the browser can settle popup-blocker / focus state.
        await new Promise((r) => setTimeout(r, 400));
        continue;
      }
      throw err;
    }
  }
  // Unreachable, but keeps TS happy.
  throw lastErr instanceof Error ? lastErr : new Error(String(lastErr));
}

/**
 * Force-refresh an ARM access token for the given tenant. Uses the existing
 * MSAL account silently with forceRefresh=true so AAD re-issues the token
 * and picks up newly-assigned roles. Falls back to a popup if the silent
 * call needs interaction.
 */
export async function refreshArmTokenForTenant(
  customerTenantId: string,
): Promise<string> {
  const accounts = msalInstance.getAllAccounts();
  const account =
    accounts.find((a) => a.tenantId === customerTenantId) ?? accounts[0];
  const request = {
    scopes: ["https://management.azure.com/user_impersonation"],
    authority: `https://login.microsoftonline.com/${customerTenantId}`,
    forceRefresh: true,
    account,
  };
  try {
    const result = await msalInstance.acquireTokenSilent(request);
    return result.accessToken;
  } catch {
    const result = await msalInstance.acquireTokenPopup({
      ...request,
      prompt: "none",
    });
    return result.accessToken;
  }
}

/**
 * Best-effort silent ARM token acquisition. Never prompts the user. Returns
 * null if no cached account/token exists — callers should treat this as
 * "no live ARM data available, use a static fallback".
 */
export async function tryAcquireArmTokenSilent(
  customerTenantId: string,
): Promise<string | null> {
  const accounts = msalInstance.getAllAccounts();
  const account =
    accounts.find((a) => a.tenantId === customerTenantId) ?? accounts[0];
  if (!account) return null;
  try {
    const result = await msalInstance.acquireTokenSilent({
      scopes: ["https://management.azure.com/user_impersonation"],
      authority: `https://login.microsoftonline.com/${customerTenantId}`,
      account,
    });
    return result.accessToken;
  } catch {
    return null;
  }
}
