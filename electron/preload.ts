import electron from "electron";
import { randomUUID } from "node:crypto";

const { contextBridge, ipcRenderer } = electron;

type UnlistenFn = () => void | Promise<void>;

interface DesktopWatchOptions {
  delayMs?: number;
}

interface DesktopDialogOptions {
  mode?: "open" | "save";
  multiple?: boolean;
  directory?: boolean;
  recursive?: boolean;
  title?: string;
  defaultPath?: string;
}

interface DesktopWindowProgressState {
  progress: number;
  status?: "none" | "normal" | "error" | "paused" | "indeterminate";
}

interface DesktopOAuthStartOptions {
  response?: string;
  ports?: number[];
}

interface DesktopBackendEventEnvelope<T = unknown> {
  event: string;
  payload: T;
}

interface DesktopStoreChangeEvent {
  storeName: string;
  key: string;
  value: unknown;
}

interface FsWatchEventPayload {
  watchId: string;
}

interface ElectronBridge {
  invoke<T>(command: string, payload?: unknown): Promise<T>;
  addBackendEventListener(
    listener: (event: DesktopBackendEventEnvelope) => void,
  ): UnlistenFn;
  storeGet<T>(storeName: string, key: string): Promise<T | undefined>;
  storeSet(storeName: string, key: string, value: unknown): Promise<void>;
  storeSave(storeName: string): Promise<void>;
  addStoreChangeListener(
    listener: (event: DesktopStoreChangeEvent) => void,
  ): UnlistenFn;
  watchPath(
    targetPath: string,
    options: DesktopWatchOptions | undefined,
    listener: () => void,
  ): Promise<UnlistenFn>;
  joinPath(...segments: string[]): Promise<string>;
  openDialog(options: DesktopDialogOptions): Promise<string | string[] | null>;
  openExternal(url: string): Promise<void>;
  openPath(targetPath: string): Promise<void>;
  readClipboardText(): Promise<string>;
  writeClipboardText(text: string): Promise<void>;
  platform(): Promise<string>;
  getAppVersion(): Promise<string>;
  getRuntimeVersion(): Promise<string>;
  requestCheckForUpdates(): Promise<void>;
  installUpdate(): Promise<void>;
  isAutoupdateEnabled(): Promise<boolean>;
  windowMinimize(): Promise<void>;
  windowHide(): Promise<void>;
  windowSetEnabled(enabled: boolean): Promise<void>;
  windowSetFocus(): Promise<void>;
  windowUnminimize(): Promise<void>;
  windowSetProgressBar(state: DesktopWindowProgressState): Promise<void>;
  addOpenUrlListener(listener: (urls: string[]) => void): UnlistenFn;
  startOAuthServer(options: DesktopOAuthStartOptions): Promise<number>;
  cancelOAuthServer(port: number): Promise<void>;
  addOAuthUrlListener(listener: (url: string) => void): UnlistenFn;
}

function listen<T>(
  channel: string,
  listener: (payload: T) => void,
): UnlistenFn {
  const wrapped = (_event: Electron.IpcRendererEvent, payload: T) =>
    listener(payload);
  ipcRenderer.on(channel, wrapped);
  return () => {
    ipcRenderer.removeListener(channel, wrapped);
  };
}

const api: ElectronBridge = {
  invoke(command, payload) {
    return ipcRenderer.invoke("quadrant:invoke", { command, payload });
  },
  addBackendEventListener(listener) {
    return listen("quadrant:backend-event", listener);
  },
  storeGet(storeName, key) {
    return ipcRenderer.invoke("quadrant:store:get", { storeName, key });
  },
  storeSet(storeName, key, value) {
    return ipcRenderer.invoke("quadrant:store:set", { storeName, key, value });
  },
  storeSave(storeName) {
    return ipcRenderer.invoke("quadrant:store:save", { storeName });
  },
  addStoreChangeListener(listener) {
    return listen("quadrant:store:changed", listener);
  },
  async watchPath(targetPath, options, listener) {
    const watchId = randomUUID();
    const stopListening = listen<FsWatchEventPayload>(
      "quadrant:fs-watch:event",
      (payload) => {
        if (payload.watchId === watchId) {
          listener();
        }
      },
    );
    await ipcRenderer.invoke("quadrant:fs-watch:start", {
      watchId,
      targetPath,
      options,
    });
    return async () => {
      stopListening();
      await ipcRenderer.invoke("quadrant:fs-watch:stop", { watchId });
    };
  },
  joinPath(...segments) {
    return ipcRenderer.invoke("quadrant:path:join", { segments });
  },
  openDialog(options) {
    return ipcRenderer.invoke("quadrant:dialog:open", { options });
  },
  openExternal(url) {
    return ipcRenderer.invoke("quadrant:shell:open-external", { url });
  },
  openPath(targetPath) {
    return ipcRenderer.invoke("quadrant:shell:open-path", { targetPath });
  },
  readClipboardText() {
    return ipcRenderer.invoke("quadrant:clipboard:read-text");
  },
  writeClipboardText(text) {
    return ipcRenderer.invoke("quadrant:clipboard:write-text", { text });
  },
  platform() {
    return ipcRenderer.invoke("quadrant:platform");
  },
  getAppVersion() {
    return ipcRenderer.invoke("quadrant:app-version");
  },
  getRuntimeVersion() {
    return ipcRenderer.invoke("quadrant:runtime-version");
  },
  requestCheckForUpdates() {
    return ipcRenderer.invoke("quadrant:updater:check");
  },
  installUpdate() {
    return ipcRenderer.invoke("quadrant:updater:install");
  },
  isAutoupdateEnabled() {
    return ipcRenderer.invoke("quadrant:updater:is-enabled");
  },
  windowMinimize() {
    return ipcRenderer.invoke("quadrant:window:minimize");
  },
  windowHide() {
    return ipcRenderer.invoke("quadrant:window:hide");
  },
  windowSetEnabled(enabled) {
    return ipcRenderer.invoke("quadrant:window:set-enabled", { enabled });
  },
  windowSetFocus() {
    return ipcRenderer.invoke("quadrant:window:set-focus");
  },
  windowUnminimize() {
    return ipcRenderer.invoke("quadrant:window:unminimize");
  },
  windowSetProgressBar(state) {
    return ipcRenderer.invoke("quadrant:window:set-progress-bar", { state });
  },
  addOpenUrlListener(listener) {
    const unlisten = listen("quadrant:open-url", listener);
    ipcRenderer.invoke("quadrant:open-url:listener-ready").catch((error) => {
      console.error("Failed to mark open-url listener as ready", error);
    });
    return unlisten;
  },
  startOAuthServer(options) {
    return ipcRenderer.invoke("quadrant:oauth:start", { options });
  },
  cancelOAuthServer(port) {
    return ipcRenderer.invoke("quadrant:oauth:cancel", { port });
  },
  addOAuthUrlListener(listener) {
    return listen("quadrant:oauth:url", listener);
  },
};

contextBridge.exposeInMainWorld("quadrantElectron", api);
