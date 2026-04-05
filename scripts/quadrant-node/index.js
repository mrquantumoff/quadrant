/** @format */

import { EventEmitter } from "node:events";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

function normalizeNativeModule(module) {
  if (!module) {
    return module;
  }

  if (typeof module.QuadrantHostAddon === "function") {
    return module;
  }

  if (
    module.default &&
    typeof module.default.QuadrantHostAddon === "function"
  ) {
    return module.default;
  }

  return module;
}

function resolveModuleSpecifier(specifier) {
  if (
    specifier.startsWith("./") ||
    specifier.startsWith("../") ||
    specifier.startsWith("/") ||
    /^[A-Za-z]:[\\/]/.test(specifier)
  ) {
    return pathToFileURL(path.resolve(process.cwd(), specifier)).href;
  }

  return specifier;
}

async function loadNativeModule() {
  if (process.env.QUADRANT_NAPI_MODULE) {
    try {
      return normalizeNativeModule(
        await import(resolveModuleSpecifier(process.env.QUADRANT_NAPI_MODULE)),
      );
    } catch (error) {
      throw new Error(
        `Failed to load Quadrant native module from ${process.env.QUADRANT_NAPI_MODULE}: ${error}`,
      );
    }
  }

  try {
    return normalizeNativeModule(await import("./native/index.js"));
  } catch (error) {
    const packageDir = path.dirname(fileURLToPath(import.meta.url));
    throw new Error(
      `Failed to load Quadrant native module from ${packageDir}: ${error}`,
    );
  }
}

const defaultNativeModule = await loadNativeModule();

function nativeMethod(target, ...names) {
  for (const name of names) {
    if (typeof target[name] === "function") {
      return target[name].bind(target);
    }
  }
  throw new Error(`Native method not found. Tried: ${names.join(", ")}`);
}

function mapOptions(options) {
  const mappedOptions = {
    dataDir: options.dataDir,
    oauthClientId: options.oauthClientId,
    oauthClientSecret: options.oauthClientSecret,
    quadrantApiKey: options.quadrantApiKey,
  };

  if (options.mcFolder != null) {
    mappedOptions.mcFolder = options.mcFolder;
  }
  if (options.apiBaseUrl != null) {
    mappedOptions.apiBaseUrl = options.apiBaseUrl;
  }
  if (options.configStoreName != null) {
    mappedOptions.configStoreName = options.configStoreName;
  }
  if (options.updateStoreName != null) {
    mappedOptions.updateStoreName = options.updateStoreName;
  }
  if (options.keyringServiceName != null) {
    mappedOptions.keyringServiceName = options.keyringServiceName;
  }
  if (options.appVersion != null) {
    mappedOptions.appVersion = options.appVersion;
  }
  if (options.osName != null) {
    mappedOptions.osName = options.osName;
  }
  if (options.userAgent != null) {
    mappedOptions.userAgent = options.userAgent;
  }

  return mappedOptions;
}

export function createQuadrantClient(
  options,
  nativeModule = defaultNativeModule,
) {
  const host = new nativeModule.QuadrantHostAddon(mapOptions(options));
  const emitter = new EventEmitter();

  nativeMethod(
    host,
    "onEvent",
    "on_event",
  )((rawEvent) => {
    const event =
      typeof rawEvent === "string" ? JSON.parse(rawEvent) : rawEvent;
    emitter.emit("event", event);
    emitter.emit(event.event, event.payload);
  });

  return {
    startBackgroundWorkers: () =>
      nativeMethod(
        host,
        "startBackgroundWorkers",
        "start_background_workers",
      )(),
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
