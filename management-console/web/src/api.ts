import { msalInstance, apiScopes } from "./auth";

// Same-origin: nginx proxies /api/* to the API container.
const apiBase = (import.meta.env.VITE_API_BASE_URL as string) || "/api";

async function token(): Promise<string> {
  const account = msalInstance.getAllAccounts()[0];
  if (!account) throw new Error("Not signed in");
  const result = await msalInstance.acquireTokenSilent({
    scopes: apiScopes,
    account,
  });
  return result.accessToken;
}

export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const t = await token();
  const resp = await fetch(`${apiBase}${path}`, {
    ...init,
    headers: {
      ...(init.headers || {}),
      Authorization: `Bearer ${t}`,
      "Content-Type": "application/json",
    },
  });
  if (!resp.ok) {
    // Prefer ProblemDetails / structured error bodies (UseExceptionHandler +
    // AddProblemDetails on the API). Fall back to raw text on parse failure.
    const text = await resp.text();
    let message = `${resp.status}`;
    try {
      const body = JSON.parse(text) as {
        title?: string;
        detail?: string;
        message?: string;
        error?: string;
      };
      const summary =
        body.detail || body.message || body.title || body.error;
      if (summary) message = `${resp.status} ${summary}`;
      else if (text) message = `${resp.status} ${text}`;
    } catch {
      if (text) message = `${resp.status} ${text}`;
    }
    throw new Error(message);
  }
  // 204 No Content (e.g. DELETE) has no body — don't try to JSON-parse it.
  if (resp.status === 204) return undefined as T;
  return resp.json() as Promise<T>;
}
