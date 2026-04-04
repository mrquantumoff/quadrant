import { EventEmitter } from "node:events";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);

function loadNativeModule() {
  if (process.env.QUADRANT_NAPI_MODULE) {
    return require(process.env.QUADRANT_NAPI_MODULE);
  }

  return require("../../src-tauri/crates/quadrant-napi/index.js");
}

function nativeMethod(target, ...names) {
  for (const name of names) {
    if (typeof target[name] === "function") {
      return target[name].bind(target);
    }
  }
  throw new Error(`Native method not found. Tried: ${names.join(", ")}`);
}

function mapOptions(options) {
  return {
    data_dir: options.dataDir,
    mc_folder: options.mcFolder ?? null,
    api_base_url: options.apiBaseUrl ?? null,
    oauth_client_id: options.oauthClientId,
    oauth_client_secret: options.oauthClientSecret,
    quadrant_api_key: options.quadrantApiKey,
    config_store_name: options.configStoreName ?? null,
    update_store_name: options.updateStoreName ?? null,
    keyring_service_name: options.keyringServiceName ?? null,
    app_version: options.appVersion ?? null,
    os_name: options.osName ?? null,
    user_agent: options.userAgent ?? null,
  };
}

export function createQuadrantClient(options, nativeModule = loadNativeModule()) {
  const host = new nativeModule.QuadrantHostAddon(mapOptions(options));
  const emitter = new EventEmitter();

  nativeMethod(host, "onEvent", "on_event")((rawEvent) => {
    const event = typeof rawEvent === "string" ? JSON.parse(rawEvent) : rawEvent;
    emitter.emit("event", event);
    emitter.emit(event.event, event.payload);
  });

  return {
    startBackgroundWorkers: () =>
      nativeMethod(host, "startBackgroundWorkers", "start_background_workers")(),
    stopBackgroundWorkers: () =>
      nativeMethod(host, "stopBackgroundWorkers", "stop_background_workers")(),
    shutdown: () => nativeMethod(host, "shutdown")(),
    initConfig: () => nativeMethod(host, "initConfig", "init_config")(),
    getMinecraftFolder: () =>
      nativeMethod(host, "getMinecraftFolder", "get_minecraft_folder")(),
    invoke: (command, payload = null) =>
      nativeMethod(host, "invoke")(command, payload),
    getModpacks: (hideFree = false) =>
      nativeMethod(host, "getModpacks", "get_modpacks")(hideFree),
    getAccountInfo: () =>
      nativeMethod(host, "getAccountInfo", "get_account_info")(),
    getNews: () => nativeMethod(host, "getNews", "get_news")(),
    installMod: (args) => nativeMethod(host, "installMod", "install_mod")(args),
    syncModpack: (modpack, overwrite = true) =>
      nativeMethod(host, "syncModpack", "sync_modpack")(modpack, overwrite),
    on: (eventName, listener) => {
      emitter.on(eventName, listener);
      return () => emitter.off(eventName, listener);
    },
    off: (eventName, listener) => {
      emitter.off(eventName, listener);
    },
    once: (eventName, listener) => {
      emitter.once(eventName, listener);
    },
  };
}
