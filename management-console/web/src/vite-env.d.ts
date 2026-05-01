/// <reference types="vite/client" />
interface ImportMetaEnv {
  readonly VITE_API_BASE_URL: string;
  readonly VITE_API_CLIENT_ID: string;
  readonly VITE_SPA_CLIENT_ID: string;
  readonly VITE_TENANT_ID: string;
}
interface ImportMeta {
  readonly env: ImportMetaEnv;
}
