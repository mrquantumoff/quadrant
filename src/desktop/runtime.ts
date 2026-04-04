import type { RuntimeAdapter } from "./contract";
import { browserRuntime } from "./browser";

let runtimePromise: Promise<RuntimeAdapter> | undefined;

function resolveRuntime(): Promise<RuntimeAdapter> {
  // Electron is checked first because its preload bridge is explicit and
  // should win whenever the renderer is hosted inside the Electron shell.
  if (window.quadrantElectron) {
    return import("./electron").then((module) => module.electronRuntime);
  }

  // Tauri injects globals into the webview, which makes it safe to lazy-load
  // the Tauri adapter only when we know we are inside that shell.
  if ("__TAURI_INTERNALS__" in window || "__TAURI__" in window) {
    return import("./tauri").then((module) => module.tauriRuntime);
  }

  // The browser adapter keeps Storybook/tests/plain Vite previews usable even
  // when no desktop shell is available.
  return Promise.resolve(browserRuntime);
}

export function getRuntimeAdapter(): Promise<RuntimeAdapter> {
  if (!runtimePromise) {
    runtimePromise = resolveRuntime();
  }
  return runtimePromise;
}
