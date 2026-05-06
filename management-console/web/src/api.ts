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
    // AddProblemDetails on the API). Fall back to raw text, then statusText.
    const text = await resp.text();
    const statusLabel = resp.statusText
      ? `${resp.status} ${resp.statusText}`
      : `${resp.status}`;
    let message = statusLabel;
    try {
      const body = JSON.parse(text) as {
        title?: string;
        detail?: string;
        message?: string;
        error?: string;
        innerError?: string;
        traceId?: string;
        errors?: Record<string, string[]>;
      };
      // Validation errors (400 from ASP.NET model binding) come as
      // { errors: { field: ["msg1", "msg2"] } } — flatten to a readable list.
      const validationMsgs = body.errors
        ? Object.entries(body.errors)
            .flatMap(([field, msgs]) =>
              (msgs as string[]).map((m) => `${field}: ${m}`),
            )
            .join("; ")
        : "";
      // Prefer the most specific signal: detail > message > validation > title > error.
      const summary =
        body.detail ||
        body.message ||
        validationMsgs ||
        body.title ||
        body.error;
      const parts: string[] = [statusLabel];
      if (summary) parts.push(summary);
      if (body.innerError && body.innerError !== summary) {
        parts.push(`(${body.innerError})`);
      }
      if (body.traceId) parts.push(`[trace ${body.traceId}]`);
      message = parts.join(" ");
      // If body parsed but yielded nothing useful, fall through to raw text.
      if (!summary && !validationMsgs && text) {
        message = `${statusLabel} ${text}`;
      }
    } catch {
      if (text) message = `${statusLabel} ${text}`;
    }
    throw new Error(message);
  }
  // 204 No Content (e.g. DELETE) has no body — don't try to JSON-parse it.
  if (resp.status === 204) return undefined as T;
  return resp.json() as Promise<T>;
}
