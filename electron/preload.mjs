import { contextBridge, ipcRenderer } from "electron";
import { randomUUID } from "node:crypto";

function listen(channel, listener) {
  const wrapped = (_event, payload) => listener(payload);
  ipcRenderer.on(channel, wrapped);
  return () => {
    ipcRenderer.removeListener(channel, wrapped);
  };
}

const api = {
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
    const stopListening = listen("quadrant:fs-watch:event", (payload) => {
      if (payload.watchId === watchId) {
        listener();
      }
    });
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
