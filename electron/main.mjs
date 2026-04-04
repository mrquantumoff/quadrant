import {
  app,
  BrowserWindow,
  Menu,
  Tray,
  clipboard,
  dialog,
  ipcMain,
  nativeTheme,
  shell,
} from "electron";
import electronUpdater from "electron-updater";
import chokidar from "chokidar";
import { createQuadrantClient } from "@quadrant/quadrant-node";
import fs from "node:fs";
import fsPromises from "node:fs/promises";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, "..");
const appId = "dev.mrquantumoff.mcmodpackmanager";
const schemes = ["quadrantnext", "curseforge", "modrinth"];
const { autoUpdater } = electronUpdater;
const packageMetadata = JSON.parse(
  fs.readFileSync(path.join(rootDir, "package.json"), "utf8"),
);
const quadrantAppVersion =
  typeof packageMetadata.version === "string" &&
  packageMetadata.version.trim().length > 0
    ? packageMetadata.version.trim()
    : app.getVersion();

app.setPath("userData", path.join(app.getPath("appData"), appId));

const argv = process.argv.slice(1);
const isAutostart = argv.includes("--autostart");
const updaterDisabledByCli = argv.includes("--noupdater");
const devServerUrl = process.env.QUADRANT_ELECTRON_DEV_SERVER_URL;

let mainWindow = null;
let tray = null;
let quadrantClient = null;
let updaterConfigured = false;
let updateDownloaded = false;
const storeCache = new Map();
const watchRegistry = new Map();
const oauthServers = new Map();
const pendingDeepLinks = [];

function broadcast(channel, payload) {
  for (const window of BrowserWindow.getAllWindows()) {
    window.webContents.send(channel, payload);
  }
}

function parseDeepLinkUrls(values) {
  return values.filter((value) =>
    schemes.some((scheme) => value.startsWith(`${scheme}:`)),
  );
}

function flushPendingDeepLinks() {
  if (pendingDeepLinks.length === 0) {
    return;
  }
  const urls = pendingDeepLinks.splice(0, pendingDeepLinks.length);
  broadcast("quadrant:open-url", urls);
}

function loadGeneratedRuntimeConfig() {
  const runtimeConfigPath = path.join(
    rootDir,
    "electron",
    "runtime-config.generated.json",
  );

  if (!fs.existsSync(runtimeConfigPath)) {
    return {};
  }

  return JSON.parse(fs.readFileSync(runtimeConfigPath, "utf8"));
}

function normalizeOptionalConfigValue(value) {
  if (typeof value !== "string") {
    return value ?? null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function normalizeRequiredConfigValue(value) {
  if (typeof value !== "string") {
    return "";
  }

  return value.trim();
}

function getRuntimeConfig() {
  const generated = loadGeneratedRuntimeConfig();
  return {
    oauthClientId: normalizeRequiredConfigValue(
      process.env.QUADRANT_OAUTH2_CLIENT_ID ?? generated.oauthClientId,
    ),
    oauthClientSecret: normalizeRequiredConfigValue(
      process.env.QUADRANT_OAUTH2_CLIENT_SECRET ?? generated.oauthClientSecret,
    ),
    quadrantApiKey: normalizeRequiredConfigValue(
      process.env.QUADRANT_API_KEY ?? generated.quadrantApiKey,
    ),
    apiBaseUrl: normalizeOptionalConfigValue(
      process.env.QUADRANT_API_BASE_URL ?? generated.apiBaseUrl,
    ),
  };
}

function ensureRuntimeSecrets(config) {
  if (!config.oauthClientId || !config.oauthClientSecret || !config.quadrantApiKey) {
    throw new Error(
      "Electron runtime config is incomplete. Run with QUADRANT_OAUTH2_CLIENT_ID, QUADRANT_OAUTH2_CLIENT_SECRET, and QUADRANT_API_KEY available.",
    );
  }
}

function getWindow() {
  if (!mainWindow) {
    throw new Error("Main window is not ready");
  }
  return mainWindow;
}

function resolveIconPath() {
  return path.join(rootDir, "src-tauri", "icons", "128x128.png");
}

function resolveTrayIconPath() {
  return path.join(rootDir, "public", "tray.png");
}

function storeFilePath(storeName) {
  return path.join(app.getPath("userData"), storeName);
}

async function readStore(storeName) {
  if (storeCache.has(storeName)) {
    return storeCache.get(storeName);
  }

  const filePath = storeFilePath(storeName);
  await fsPromises.mkdir(path.dirname(filePath), { recursive: true });

  let data = {};
  if (fs.existsSync(filePath)) {
    try {
      data = JSON.parse(await fsPromises.readFile(filePath, "utf8"));
    } catch (error) {
      console.warn(`Failed to parse ${filePath}`, error);
    }
  }

  storeCache.set(storeName, data);
  return data;
}

async function saveStore(storeName) {
  const data = await readStore(storeName);
  const filePath = storeFilePath(storeName);
  await fsPromises.mkdir(path.dirname(filePath), { recursive: true });
  await fsPromises.writeFile(filePath, JSON.stringify(data, null, 2));
}

async function setStoreValue(storeName, key, value) {
  const data = await readStore(storeName);
  data[key] = value;
  storeCache.set(storeName, data);
  await saveStore(storeName);
  broadcast("quadrant:store:changed", { storeName, key, value });
}

function queueDeepLinks(urls) {
  if (urls.length === 0) {
    return;
  }
  pendingDeepLinks.push(...urls);
  if (mainWindow) {
    flushPendingDeepLinks();
  }
}

async function createQuadrantHostClient() {
  if (quadrantClient) {
    return quadrantClient;
  }

  const runtimeConfig = getRuntimeConfig();
  ensureRuntimeSecrets(runtimeConfig);

  quadrantClient = createQuadrantClient({
    dataDir: app.getPath("userData"),
    apiBaseUrl: runtimeConfig.apiBaseUrl,
    oauthClientId: runtimeConfig.oauthClientId,
    oauthClientSecret: runtimeConfig.oauthClientSecret,
    quadrantApiKey: runtimeConfig.quadrantApiKey,
    appVersion: quadrantAppVersion,
    osName: process.platform.toUpperCase(),
    userAgent: `Quadrant/${quadrantAppVersion} Electron/${process.versions.electron}`,
  });

  quadrantClient.on("event", (event) => {
    broadcast("quadrant:backend-event", event);
  });

  await quadrantClient.initConfig();
  try {
    await quadrantClient.startBackgroundWorkers();
  } catch (error) {
    console.error("Failed to start background workers", error);
  }

  quadrantClient
    .invoke("get_versions")
    .catch((error) =>
      console.warn("Failed to warm Minecraft versions cache", error),
    );

  return quadrantClient;
}

async function configureUpdater() {
  if (updaterConfigured) {
    return;
  }

  autoUpdater.autoDownload = true;
  autoUpdater.autoInstallOnAppQuit = false;

  const updateStore = await readStore("updateConfig.json");
  const channel = updateStore.channel ?? "stable";
  autoUpdater.allowPrerelease = channel !== "stable";
  updaterConfigured = true;

  autoUpdater.on("download-progress", (progress) => {
    broadcast("quadrant:backend-event", {
      event: "updateDownloadProgress",
      payload: progress.percent / 100,
    });
  });

  autoUpdater.on("update-downloaded", () => {
    updateDownloaded = true;
    broadcast("quadrant:backend-event", {
      event: "updateDownloadProgress",
      payload: 1,
    });
  });

  autoUpdater.on("update-not-available", () => {
    updateDownloaded = false;
  });
}

function isAutoupdateEnabled() {
  return app.isPackaged && !updaterDisabledByCli;
}

async function requestCheckForUpdates() {
  if (!isAutoupdateEnabled()) {
    return;
  }

  await configureUpdater();
  await autoUpdater.checkForUpdates();
}

function createMainWindow() {
  nativeTheme.themeSource = "dark";

  const window = new BrowserWindow({
    title: "Quadrant",
    width: 1280,
    height: 720,
    minWidth: 1280,
    minHeight: 720,
    show: false,
    frame: false,
    backgroundColor: "#020617",
    icon: resolveIconPath(),
    webPreferences: {
      preload: path.join(__dirname, "preload.mjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });

  window.on("ready-to-show", () => {
    if (isAutostart) {
      window.hide();
      return;
    }
    window.show();
  });

  window.on("closed", () => {
    if (mainWindow === window) {
      mainWindow = null;
    }
  });

  if (devServerUrl) {
    window.loadURL(devServerUrl);
    window.webContents.openDevTools({ mode: "detach" });
  } else {
    window.loadFile(path.join(rootDir, "dist", "index.html"));
  }

  return window;
}

function showMainWindow() {
  if (!mainWindow) {
    return;
  }
  mainWindow.show();
  mainWindow.focus();
  if (mainWindow.isMinimized()) {
    mainWindow.restore();
  }
}

function toggleMainWindowVisibility() {
  if (!mainWindow) {
    return;
  }

  if (mainWindow.isVisible()) {
    mainWindow.hide();
  } else {
    showMainWindow();
  }
}

function createTray() {
  const nextTray = new Tray(resolveTrayIconPath());
  const menu = Menu.buildFromTemplate([
    {
      label: "Show/Hide",
      click: () => {
        toggleMainWindowVisibility();
      },
    },
    {
      label: "Quit",
      click: () => {
        app.quit();
      },
    },
  ]);

  nextTray.setToolTip("Quadrant");
  nextTray.setContextMenu(menu);
  nextTray.on("click", () => {
    toggleMainWindowVisibility();
  });

  return nextTray;
}

function registerProtocolHandlers() {
  for (const scheme of schemes) {
    if (process.defaultApp) {
      if (process.argv.length >= 2) {
        app.setAsDefaultProtocolClient(scheme, process.execPath, [
          path.resolve(process.argv[1]),
        ]);
      }
      continue;
    }
    app.setAsDefaultProtocolClient(scheme);
  }
}

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
}

app.on("second-instance", (_event, commandLine) => {
  showMainWindow();
  queueDeepLinks(parseDeepLinkUrls(commandLine));
});

app.on("open-url", (event, url) => {
  event.preventDefault();
  queueDeepLinks([url]);
});

app.whenReady().then(async () => {
  registerProtocolHandlers();
  mainWindow = createMainWindow();
  tray = createTray();

  await createQuadrantHostClient();
  flushPendingDeepLinks();
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

app.on("activate", () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    mainWindow = createMainWindow();
    flushPendingDeepLinks();
    return;
  }
  showMainWindow();
});

app.on("before-quit", async () => {
  for (const watcher of watchRegistry.values()) {
    await watcher.close();
  }
  watchRegistry.clear();

  for (const server of oauthServers.values()) {
    server.close();
  }
  oauthServers.clear();

  if (quadrantClient) {
    try {
      await quadrantClient.shutdown();
    } catch (error) {
      console.error("Failed to shut down Quadrant client", error);
    }
  }
});

ipcMain.handle("quadrant:invoke", async (_event, { command, payload }) => {
  const client = await createQuadrantHostClient();
  return client.invoke(command, payload ?? null);
});

ipcMain.handle("quadrant:store:get", async (_event, { storeName, key }) => {
  const store = await readStore(storeName);
  return store[key];
});

ipcMain.handle("quadrant:store:set", async (_event, { storeName, key, value }) => {
  await setStoreValue(storeName, key, value);
});

ipcMain.handle("quadrant:store:save", async (_event, { storeName }) => {
  await saveStore(storeName);
});

ipcMain.handle("quadrant:fs-watch:start", async (event, { watchId, targetPath, options }) => {
  const watcher = chokidar.watch(targetPath, {
    ignoreInitial: true,
    awaitWriteFinish: options?.delayMs
      ? {
          stabilityThreshold: options.delayMs,
          pollInterval: Math.max(50, Math.floor(options.delayMs / 2)),
        }
      : false,
  });
  const sendChange = () => {
    event.sender.send("quadrant:fs-watch:event", { watchId });
  };
  watcher.on("add", sendChange);
  watcher.on("change", sendChange);
  watcher.on("unlink", sendChange);
  watcher.on("addDir", sendChange);
  watcher.on("unlinkDir", sendChange);
  watchRegistry.set(watchId, watcher);
});

ipcMain.handle("quadrant:fs-watch:stop", async (_event, { watchId }) => {
  const watcher = watchRegistry.get(watchId);
  if (watcher) {
    await watcher.close();
    watchRegistry.delete(watchId);
  }
});

ipcMain.handle("quadrant:path:join", async (_event, { segments }) => {
  return path.join(...segments);
});

ipcMain.handle("quadrant:dialog:open", async (_event, { options }) => {
  const result = await dialog.showOpenDialog(getWindow(), {
    title: options?.title,
    properties: [
      options?.directory ? "openDirectory" : "openFile",
      ...(options?.multiple ? ["multiSelections"] : []),
      ...(options?.directory && options?.recursive ? ["createDirectory"] : []),
    ],
    defaultPath: options?.defaultPath,
  });

  if (result.canceled) {
    return null;
  }

  if (options?.multiple) {
    return result.filePaths;
  }

  return result.filePaths[0] ?? null;
});

ipcMain.handle("quadrant:shell:open-external", async (_event, { url }) => {
  await shell.openExternal(url);
});

ipcMain.handle("quadrant:shell:open-path", async (_event, { targetPath }) => {
  const errorMessage = await shell.openPath(targetPath);
  if (errorMessage) {
    throw new Error(errorMessage);
  }
});

ipcMain.handle("quadrant:clipboard:read-text", async () => clipboard.readText());
ipcMain.handle("quadrant:clipboard:write-text", async (_event, { text }) => {
  clipboard.writeText(text);
});

ipcMain.handle("quadrant:platform", async () => process.platform);
ipcMain.handle("quadrant:app-version", async () => quadrantAppVersion);
ipcMain.handle("quadrant:runtime-version", async () => process.versions.electron);

ipcMain.handle("quadrant:updater:check", async () => {
  await requestCheckForUpdates();
});

ipcMain.handle("quadrant:updater:install", async () => {
  if (!updateDownloaded) {
    throw new Error("No downloaded update is available");
  }
  autoUpdater.quitAndInstall();
});

ipcMain.handle("quadrant:updater:is-enabled", async () => isAutoupdateEnabled());

ipcMain.handle("quadrant:window:minimize", async () => {
  getWindow().minimize();
});

ipcMain.handle("quadrant:window:hide", async () => {
  getWindow().hide();
});

ipcMain.handle("quadrant:window:set-enabled", async (_event, { enabled }) => {
  getWindow().setEnabled(enabled);
});

ipcMain.handle("quadrant:window:set-focus", async () => {
  getWindow().focus();
});

ipcMain.handle("quadrant:window:unminimize", async () => {
  const window = getWindow();
  if (window.isMinimized()) {
    window.restore();
  }
});

ipcMain.handle("quadrant:window:set-progress-bar", async (_event, { state }) => {
  const window = getWindow();
  const normalizedProgress =
    typeof state.progress === "number" && state.progress <= 1
      ? state.progress
      : state.progress / 100;
  const progress = state.status === "none" ? -1 : normalizedProgress;
  window.setProgressBar(progress);
});

ipcMain.handle("quadrant:oauth:start", async (_event, { options }) => {
  const responseHtml =
    options?.response ??
    "<html><body><h1>You can return to Quadrant now.</h1></body></html>";
  const ports = options?.ports ?? [4000, 4001, 4002, 4003, 4004, 4005];

  for (const port of ports) {
    try {
      const server = http.createServer((request, response) => {
        const url = `http://127.0.0.1:${port}${request.url ?? "/"}`;
        broadcast("quadrant:oauth:url", url);
        response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
        response.end(responseHtml);
      });

      await new Promise((resolve, reject) => {
        server.once("error", reject);
        server.listen(port, "127.0.0.1", () => resolve(undefined));
      });

      oauthServers.set(port, server);
      return port;
    } catch (error) {
      console.warn(`Failed to bind OAuth server on ${port}`, error);
    }
  }

  throw new Error("No available OAuth callback port");
});

ipcMain.handle("quadrant:oauth:cancel", async (_event, { port }) => {
  const server = oauthServers.get(port);
  if (!server) {
    return;
  }

  await new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(undefined);
    });
  });
  oauthServers.delete(port);
});
