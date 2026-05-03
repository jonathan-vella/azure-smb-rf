import React, { useEffect, useState } from "react";
import ReactDOM from "react-dom/client";
import {
  BrowserRouter,
  Routes,
  Route,
  Navigate,
  Link,
  NavLink,
} from "react-router-dom";
import { MsalProvider, useMsal, useIsAuthenticated } from "@azure/msal-react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { FluentProvider, Button, Switch } from "@fluentui/react-components";
import { msalInstance, apiScopes } from "./auth";
import { lightTheme, darkTheme } from "./fluentTheme";
import { CustomersPage } from "./pages/CustomersPage";
import { CustomerDetailPage } from "./pages/CustomerDetailPage";
import { OnboardCustomerPage } from "./pages/OnboardCustomerPage";
import { DeployPage } from "./pages/DeployPage";
import { DeploymentDetailPage } from "./pages/DeploymentDetailPage";
import { CustomerPrerequisitesPage } from "./pages/CustomerPrerequisitesPage";
import { SettingsPage } from "./pages/SettingsPage";
import "./theme.css";

const qc = new QueryClient();

function useColorMode() {
  const [mode, setMode] = useState<"light" | "dark">(() => {
    const saved = localStorage.getItem("console.theme");
    if (saved === "light" || saved === "dark") return saved;
    return window.matchMedia?.("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light";
  });
  useEffect(() => {
    document.documentElement.dataset.theme = mode;
    localStorage.setItem("console.theme", mode);
  }, [mode]);
  return [mode, setMode] as const;
}

function NavBtn({ to, children }: { to: string; children: React.ReactNode }) {
  return (
    <NavLink
      to={to}
      style={({ isActive }) => ({
        textDecoration: "none",
        padding: "6px 12px",
        borderRadius: 6,
        fontSize: "0.9rem",
        color: isActive ? "var(--azure-mid)" : "var(--text-muted)",
        background: isActive ? "var(--surface-3)" : "transparent",
        fontWeight: isActive ? 600 : 500,
      })}
    >
      {children}
    </NavLink>
  );
}

function AppBar({
  mode,
  onToggle,
}: {
  mode: "light" | "dark";
  onToggle: () => void;
}) {
  const { instance, accounts } = useMsal();
  const user = accounts[0]?.username;
  return (
    <header className="app-bar">
      <Link to="/customers" className="app-bar__brand">
        <img src="/favicon.svg" alt="" className="app-bar__brand-mark" />
        <span>SMB Ready Foundation</span>
      </Link>
      <nav style={{ display: "flex", gap: 8, marginLeft: 12 }}>
        <NavBtn to="/customers">Customers</NavBtn>
        <NavBtn to="/settings">Settings</NavBtn>
      </nav>
      <div className="app-bar__spacer" />
      <Switch
        checked={mode === "dark"}
        onChange={onToggle}
        label={mode === "dark" ? "Dark" : "Light"}
      />
      {user && <span className="app-bar__user">{user}</span>}
      <Button
        size="small"
        appearance="subtle"
        onClick={() =>
          instance.logoutRedirect({
            postLogoutRedirectUri: window.location.origin,
          })
        }
      >
        Sign out
      </Button>
    </header>
  );
}

function Shell({
  children,
  mode,
  onToggle,
}: {
  children: React.ReactNode;
  mode: "light" | "dark";
  onToggle: () => void;
}) {
  const { instance } = useMsal();
  const authed = useIsAuthenticated();
  if (!authed) {
    return (
      <div className="signin">
        <div className="signin__panel">
          <h1>SMB Ready Foundation</h1>
          <p style={{ color: "var(--text-muted)" }}>
            Partner management console — sign in with your partner-tenant
            account to onboard customers and deploy landing zones.
          </p>
          <Button
            appearance="primary"
            size="large"
            onClick={() => instance.loginRedirect({ scopes: apiScopes })}
          >
            Sign in
          </Button>
        </div>
      </div>
    );
  }
  return (
    <div className="app-shell">
      <AppBar mode={mode} onToggle={onToggle} />
      <main className="app-content">{children}</main>
    </div>
  );
}

function Root() {
  const [mode, setMode] = useColorMode();
  const theme = mode === "dark" ? darkTheme : lightTheme;
  return (
    <FluentProvider theme={theme}>
      <BrowserRouter>
        <Shell
          mode={mode}
          onToggle={() => setMode(mode === "dark" ? "light" : "dark")}
        >
          <Routes>
            <Route path="/" element={<Navigate to="/customers" replace />} />
            <Route path="/customers" element={<CustomersPage />} />
            <Route
              path="/customers/onboard"
              element={<OnboardCustomerPage />}
            />
            <Route path="/customers/:id" element={<CustomerDetailPage />} />
            <Route
              path="/customers/:id/prerequisites"
              element={<CustomerPrerequisitesPage />}
            />
            <Route path="/customers/:id/deploy" element={<DeployPage />} />
            <Route
              path="/customers/:id/deployments/:depId"
              element={<DeploymentDetailPage />}
            />
            <Route path="/settings" element={<SettingsPage />} />
          </Routes>
        </Shell>
      </BrowserRouter>
    </FluentProvider>
  );
}

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <MsalProvider instance={msalInstance}>
      <QueryClientProvider client={qc}>
        <Root />
      </QueryClientProvider>
    </MsalProvider>
  </React.StrictMode>,
);
