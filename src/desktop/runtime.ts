import type { RuntimeAdapter } from "./contract";
import { browserRuntime } from "./browser";

let runtimePromise: Promise<RuntimeAdapter> | undefined;

function resolveRuntime(): Promise<RuntimeAdapter> {
  if (window.quadrantElectron) {
    return import("./electron").then((module) => module.electronRuntime);
  }

  if ("__TAURI_INTERNALS__" in window || "__TAURI__" in window) {
    return import("./tauri").then((module) => module.tauriRuntime);
  }

  return Promise.resolve(browserRuntime);
}

export function getRuntimeAdapter(): Promise<RuntimeAdapter> {
  if (!runtimePromise) {
    runtimePromise = resolveRuntime();
  }
  return runtimePromise;
}
