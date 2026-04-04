/// <reference types="vite/client" />

import type { ElectronBridge } from "./desktop/contract";

declare global {
  interface Window {
    __TAURI__?: unknown;
    __TAURI_INTERNALS__?: unknown;
    quadrantElectron?: ElectronBridge;
  }
}
