import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Button,
  Field,
  Input,
  MessageBar,
  MessageBarBody,
  MessageBarTitle,
  Spinner,
} from "@fluentui/react-components";
import { api } from "../api";

interface AppSettings {
  id: string;
  repoUrl: string;
  repoRef: string;
  updatedAt?: string;
}

interface UpdateSettingsRequest {
  repoUrl: string;
  repoRef: string;
}

export function SettingsPage() {
  const qc = useQueryClient();
  const q = useQuery({
    queryKey: ["settings"],
    queryFn: () => api<AppSettings>("/settings"),
  });

  const [repoUrl, setRepoUrl] = useState("");
  const [repoRef, setRepoRef] = useState("");
  const [saved, setSaved] = useState(false);

  // Hydrate the form once the GET resolves.
  useEffect(() => {
    if (q.data) {
      setRepoUrl(q.data.repoUrl);
      setRepoRef(q.data.repoRef);
    }
  }, [q.data]);

  const m = useMutation({
    mutationFn: (body: UpdateSettingsRequest) =>
      api<AppSettings>("/settings", {
        method: "PUT",
        body: JSON.stringify(body),
      }),
    onSuccess: (data) => {
      qc.setQueryData(["settings"], data);
      setSaved(true);
    },
  });

  if (q.isLoading) {
    return (
      <div style={{ padding: 24 }}>
        <Spinner label="Loading settings…" />
      </div>
    );
  }
  if (q.isError) {
    return (
      <div style={{ padding: 24 }}>
        <MessageBar intent="error">
          <MessageBarBody>
            <MessageBarTitle>Failed to load settings</MessageBarTitle>
            {(q.error as Error).message}
          </MessageBarBody>
        </MessageBar>
      </div>
    );
  }

  const valid = repoUrl.trim().length > 0 && repoRef.trim().length > 0;
  const dirty = q.data && (repoUrl !== q.data.repoUrl || repoRef !== q.data.repoRef);

  return (
    <div style={{ padding: 24, maxWidth: 720 }}>
      <h1 style={{ marginBottom: 4 }}>Settings</h1>
      <p style={{ color: "var(--text-muted)", marginTop: 0 }}>
        Repository the API and worker pull prerequisites and resource templates
        from. Partners can point this at a fork or an internal mirror.
      </p>

      {m.isError && (
        <MessageBar intent="error" style={{ marginBottom: 12 }}>
          <MessageBarBody>
            <MessageBarTitle>Save failed</MessageBarTitle>
            {(m.error as Error).message}
          </MessageBarBody>
        </MessageBar>
      )}
      {saved && !dirty && (
        <MessageBar intent="success" style={{ marginBottom: 12 }}>
          <MessageBarBody>Settings saved.</MessageBarBody>
        </MessageBar>
      )}

      <div style={{ display: "grid", gap: 16 }}>
        <Field
          label="Repository URL"
          hint="Full HTTPS Git URL (e.g. https://github.com/org/repo.git)"
          required
        >
          <Input
            value={repoUrl}
            onChange={(_, d) => {
              setRepoUrl(d.value);
              setSaved(false);
            }}
            placeholder="https://github.com/jonathan-vella/azure-smb-rf.git"
          />
        </Field>
        <Field
          label="Branch / tag / commit"
          hint="Git ref the API and worker should clone (e.g. main, v1.2.0)"
          required
        >
          <Input
            value={repoRef}
            onChange={(_, d) => {
              setRepoRef(d.value);
              setSaved(false);
            }}
            placeholder="main"
          />
        </Field>
        <div style={{ display: "flex", gap: 8 }}>
          <Button
            appearance="primary"
            disabled={!valid || !dirty || m.isPending}
            onClick={() =>
              m.mutate({ repoUrl: repoUrl.trim(), repoRef: repoRef.trim() })
            }
          >
            {m.isPending ? "Saving…" : "Save"}
          </Button>
          <Button
            disabled={!dirty || m.isPending}
            onClick={() => {
              if (q.data) {
                setRepoUrl(q.data.repoUrl);
                setRepoRef(q.data.repoRef);
                setSaved(false);
              }
            }}
          >
            Reset
          </Button>
        </div>
        {q.data?.updatedAt && (
          <div style={{ color: "var(--text-muted)", fontSize: "0.85rem" }}>
            Last updated {new Date(q.data.updatedAt).toLocaleString()}
          </div>
        )}
      </div>
    </div>
  );
}
