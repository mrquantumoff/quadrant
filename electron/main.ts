/**
 * eslint-disable no-undef
 *
 * @format
 */

import electron, {
	type BrowserWindow as BrowserWindowType,
	type OpenDialogOptions,
	type Tray as TrayType,
} from "electron";
import chokidar, { type FSWatcher } from "chokidar";
import electronUpdater from "electron-updater";
import {
	createQuadrantClient,
	type QuadrantClient,
	type QuadrantEventEnvelope,
} from "@quadrant/quadrant-node";
import fs from "node:fs";
import fsPromises from "node:fs/promises";
import http from "node:http";
import { randomUUID } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";

const {
	app,
	BrowserWindow,
	Menu,
	Tray,
	clipboard,
	dialog,
	ipcMain,
	nativeTheme,
	shell,
} = electron;
const { autoUpdater } = electronUpdater;

interface RuntimeConfig {
	oauthClientId: string;
	oauthClientSecret: string;
	quadrantApiKey: string;
	apiBaseUrl: string | null;
}

type RuntimeConfigFile = Partial<RuntimeConfig>;

interface StoreData {
	[key: string]: unknown;
}

interface FsWatchOptions {
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

interface WindowProgressState {
	progress: number;
	status?: "none" | "normal" | "error" | "paused" | "indeterminate";
}

interface OAuthStartOptions {
	response?: string;
	ports?: number[];
}

interface BackendEventEnvelope<T = unknown> {
	event: string;
	payload: T;
}

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, "..");
const appId = "dev.mrquantumoff.mcmodpackmanager";
const schemes = ["quadrantnext", "curseforge", "modrinth"];
const packageMetadata = JSON.parse(
	fs.readFileSync(path.join(rootDir, "package.json"), "utf8"),
) as { version?: unknown };
const quadrantAppVersion =
	(
		typeof packageMetadata.version === "string" &&
		packageMetadata.version.trim().length > 0
	) ?
		packageMetadata.version.trim()
	:	app.getVersion();

app.setPath("userData", path.join(app.getPath("appData"), appId));

const argv = process.argv.slice(1);
const isAutostart = argv.includes("--autostart");
const updaterDisabledByCli = argv.includes("--noupdater");
const apiUrlFromCli = (() => {
	const idx = argv.indexOf("--api-url");
	return idx !== -1 && idx + 1 < argv.length ? argv[idx + 1] : null;
})();
const devServerUrl = process.env.QUADRANT_ELECTRON_DEV_SERVER_URL;

let mainWindow: BrowserWindowType | null = null;
// eslint-disable-next-line @typescript-eslint/no-unused-vars
let tray: TrayType | null = null;
let quadrantClient: QuadrantClient | null = null;
let updaterConfigured = false;
let updateDownloaded = false;
const storeCache = new Map<string, StoreData>();
const storeWriteQueues = new Map<string, Promise<unknown>>();
const watchRegistry = new Map<string, FSWatcher>();
const oauthServers = new Map<number, http.Server>();
const pendingDeepLinks: string[] = [];
let openUrlRendererReady = false;

function broadcast(channel: string, payload: unknown): void {
	for (const window of BrowserWindow.getAllWindows()) {
		window.webContents.send(channel, payload);
	}
}

function parseDeepLinkUrls(values: string[]): string[] {
	return values.filter((value) =>
		schemes.some((scheme) => value.startsWith(`${scheme}:`)),
	);
}

function flushPendingDeepLinks(): void {
	if (!mainWindow || !openUrlRendererReady || pendingDeepLinks.length === 0) {
		return;
	}
	const urls = pendingDeepLinks.splice(0, pendingDeepLinks.length);
	mainWindow.webContents.send("quadrant:open-url", urls);
}

function loadGeneratedRuntimeConfig(): RuntimeConfigFile {
	const runtimeConfigPath = path.join(
		__dirname,
		"runtime-config.generated.json",
	);

	if (!fs.existsSync(runtimeConfigPath)) {
		return {};
	}

	return JSON.parse(
		fs.readFileSync(runtimeConfigPath, "utf8"),
	) as RuntimeConfigFile;
}

function normalizeOptionalConfigValue(value: unknown): string | null {
	if (typeof value !== "string") {
		return value == null ? null : String(value);
	}

	const trimmed = value.trim();
	return trimmed.length > 0 ? trimmed : null;
}

function normalizeRequiredConfigValue(value: unknown): string {
	if (typeof value !== "string") {
		return "";
	}

	return value.trim();
}

function getRuntimeConfig(): RuntimeConfig {
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

function ensureRuntimeSecrets(config: RuntimeConfig): void {
	if (
		!config.oauthClientId ||
		!config.oauthClientSecret ||
		!config.quadrantApiKey
	) {
		throw new Error(
			"Electron runtime config is incomplete. Run with QUADRANT_OAUTH2_CLIENT_ID, QUADRANT_OAUTH2_CLIENT_SECRET, and QUADRANT_API_KEY available.",
		);
	}
}

function getWindow(): BrowserWindowType {
	if (!mainWindow) {
		throw new Error("Main window is not ready");
	}
	return mainWindow;
}

function resolveIconPath(): string {
	return path.join(rootDir, "src-tauri", "icons", "128x128.png");
}

function resolveTrayIconPath(): string {
	const trayIconPath = path.join(rootDir, "public", "tray.png");
	return fs.existsSync(trayIconPath) ? trayIconPath : resolveIconPath();
}

function normalizeDesktopPlatform(platform: NodeJS.Platform): string {
	switch (platform) {
		case "win32":
			return "windows";
		case "darwin":
			return "macos";
		default:
			return platform;
	}
}

function storeFilePath(storeName: string): string {
	return path.join(app.getPath("userData"), storeName);
}

async function readStore(storeName: string): Promise<StoreData> {
	const filePath = storeFilePath(storeName);
	await fsPromises.mkdir(path.dirname(filePath), { recursive: true });

	let data: StoreData = {};
	if (fs.existsSync(filePath)) {
		try {
			data = JSON.parse(
				await fsPromises.readFile(filePath, "utf8"),
			) as StoreData;
		} catch (error) {
			if (storeCache.has(storeName)) {
				console.warn(`Failed to parse ${filePath}, using cached copy`, error);
				return storeCache.get(storeName) ?? {};
			}
			console.warn(`Failed to parse ${filePath}`, error);
		}
	}

	storeCache.set(storeName, data);
	return data;
}

async function writeStoreFile(
	filePath: string,
	data: StoreData,
): Promise<void> {
	const tempPath = `${filePath}.${randomUUID()}.tmp`;
	await fsPromises.writeFile(tempPath, JSON.stringify(data, null, 2));
	await fsPromises.rename(tempPath, filePath);
}

async function saveStore(
	storeName: string,
	dataOverride?: StoreData,
): Promise<void> {
	const data =
		dataOverride ?? storeCache.get(storeName) ?? (await readStore(storeName));
	const filePath = storeFilePath(storeName);
	await fsPromises.mkdir(path.dirname(filePath), { recursive: true });
	await writeStoreFile(filePath, data);
}

function queueStoreWrite<T>(
	storeName: string,
	operation: () => Promise<T>,
): Promise<T> {
	const previous = storeWriteQueues.get(storeName) ?? Promise.resolve();
	const next = previous.catch(() => undefined).then(operation);
	storeWriteQueues.set(storeName, next);
	return next.finally(() => {
		if (storeWriteQueues.get(storeName) === next) {
			storeWriteQueues.delete(storeName);
		}
	});
}

async function setStoreValue(
	storeName: string,
	key: string,
	value: unknown,
): Promise<void> {
	await queueStoreWrite(storeName, async () => {
		const data = await readStore(storeName);
		data[key] = value;
		storeCache.set(storeName, data);
		await saveStore(storeName, data);
	});
	broadcast("quadrant:store:changed", { storeName, key, value });
}

function queueDeepLinks(urls: string[]): void {
	if (urls.length === 0) {
		return;
	}
	pendingDeepLinks.push(...urls);
	if (mainWindow && openUrlRendererReady) {
		flushPendingDeepLinks();
	}
}

async function createQuadrantHostClient(): Promise<QuadrantClient> {
	if (quadrantClient) {
		return quadrantClient;
	}

	const runtimeConfig = getRuntimeConfig();
	ensureRuntimeSecrets(runtimeConfig);

	quadrantClient = createQuadrantClient({
		dataDir: app.getPath("userData"),
		apiBaseUrl: apiUrlFromCli ?? runtimeConfig.apiBaseUrl,
		oauthClientId: runtimeConfig.oauthClientId,
		oauthClientSecret: runtimeConfig.oauthClientSecret,
		quadrantApiKey: runtimeConfig.quadrantApiKey,
		appVersion: quadrantAppVersion,
		osName: process.platform.toUpperCase(),
		userAgent: `mrquantumoff/quadrant/${quadrantAppVersion} (mrquantumoff.dev) (QUADRANT NEXT/Electron v${process.versions.electron})`,
	});

	quadrantClient.on("event", (event: QuadrantEventEnvelope) => {
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
		.catch((error: unknown) =>
			console.warn("Failed to warm Minecraft versions cache", error),
		);

	return quadrantClient;
}

async function configureUpdater(): Promise<void> {
	const updateStore = await readStore("updateConfig.json");
	const channel =
		typeof updateStore.channel === "string" ? updateStore.channel : "stable";
	autoUpdater.allowPrerelease = channel !== "stable";

	if (updaterConfigured) {
		return;
	}

	autoUpdater.autoDownload = true;
	autoUpdater.autoInstallOnAppQuit = false;
	updaterConfigured = true;

	autoUpdater.on("download-progress", (progress) => {
		broadcast("quadrant:backend-event", {
			event: "updateDownloadProgress",
			payload: progress.percent / 100,
		} satisfies BackendEventEnvelope<number>);
	});

	autoUpdater.on("update-downloaded", () => {
		updateDownloaded = true;
		broadcast("quadrant:backend-event", {
			event: "updateDownloadProgress",
			payload: 1,
		} satisfies BackendEventEnvelope<number>);
	});

	autoUpdater.on("update-not-available", () => {
		updateDownloaded = false;
	});
}

function isAutoupdateEnabled(): boolean {
	return app.isPackaged && !updaterDisabledByCli;
}

async function requestCheckForUpdates(): Promise<void> {
	if (!isAutoupdateEnabled()) {
		return;
	}

	await configureUpdater();
	await autoUpdater.checkForUpdates();
}

function createMainWindow(): BrowserWindowType {
	openUrlRendererReady = false;
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
			preload: path.join(__dirname, "preload.js"),
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
			openUrlRendererReady = false;
			mainWindow = null;
		}
	});

	window.webContents.on("did-start-loading", () => {
		if (mainWindow === window) {
			openUrlRendererReady = false;
		}
	});

	if (devServerUrl) {
		void window.loadURL(devServerUrl);
		window.webContents.openDevTools({ mode: "detach" });
	} else {
		void window.loadFile(path.join(rootDir, "dist", "index.html"));
	}

	return window;
}

function showMainWindow(): void {
	if (!mainWindow) {
		return;
	}
	mainWindow.setEnabled(true);
	mainWindow.show();
	mainWindow.focus();
	if (mainWindow.isMinimized()) {
		mainWindow.restore();
	}
}

function toggleMainWindowVisibility(): void {
	if (!mainWindow) {
		return;
	}

	if (mainWindow.isVisible()) {
		mainWindow.hide();
	} else {
		showMainWindow();
	}
}

function createTray(): TrayType {
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

function registerProtocolHandlers(): void {
	for (const scheme of schemes) {
		if (process.defaultApp) {
			if (process.argv.length >= 2) {
				app.setAsDefaultProtocolClient(scheme, process.execPath, [
					path.resolve(process.argv[1] ?? ""),
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

queueDeepLinks(parseDeepLinkUrls(process.argv));

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
});

app.on("window-all-closed", () => {
	if (process.platform !== "darwin") {
		app.quit();
	}
});

app.on("activate", () => {
	if (BrowserWindow.getAllWindows().length === 0) {
		mainWindow = createMainWindow();
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

ipcMain.handle(
	"quadrant:invoke",
	async (_event, payload: { command: string; payload?: unknown }) => {
		const client = await createQuadrantHostClient();
		return client.invoke(payload.command, payload.payload ?? null);
	},
);

ipcMain.handle(
	"quadrant:store:get",
	async (_event, payload: { storeName: string; key: string }) => {
		const store = await readStore(payload.storeName);
		return store[payload.key];
	},
);

ipcMain.handle(
	"quadrant:store:set",
	async (
		_event,
		payload: { storeName: string; key: string; value: unknown },
	) => {
		await setStoreValue(payload.storeName, payload.key, payload.value);
	},
);

ipcMain.handle(
	"quadrant:store:save",
	async (_event, payload: { storeName: string }) => {
		await queueStoreWrite(payload.storeName, async () => {
			await saveStore(payload.storeName);
		});
	},
);

ipcMain.handle(
	"quadrant:fs-watch:start",
	async (
		event,
		payload: { watchId: string; targetPath: string; options?: FsWatchOptions },
	) => {
		const watcher = chokidar.watch(payload.targetPath, {
			ignoreInitial: true,
			awaitWriteFinish:
				payload.options?.delayMs ?
					{
						stabilityThreshold: payload.options.delayMs,
						pollInterval: Math.max(50, Math.floor(payload.options.delayMs / 2)),
					}
				:	false,
		});
		const sendChange = () => {
			event.sender.send("quadrant:fs-watch:event", {
				watchId: payload.watchId,
			});
		};
		watcher.on("add", sendChange);
		watcher.on("change", sendChange);
		watcher.on("unlink", sendChange);
		watcher.on("addDir", sendChange);
		watcher.on("unlinkDir", sendChange);
		watchRegistry.set(payload.watchId, watcher);
	},
);

ipcMain.handle(
	"quadrant:fs-watch:stop",
	async (_event, payload: { watchId: string }) => {
		const watcher = watchRegistry.get(payload.watchId);
		if (watcher) {
			await watcher.close();
			watchRegistry.delete(payload.watchId);
		}
	},
);

ipcMain.handle(
	"quadrant:path:join",
	async (_event, payload: { segments: string[] }) =>
		path.join(...payload.segments),
);

ipcMain.handle(
	"quadrant:dialog:open",
	async (_event, payload: { options?: DesktopDialogOptions }) => {
		const { options } = payload;

		if (options?.mode === "save") {
			const result = await dialog.showSaveDialog(getWindow(), {
				title: options.title,
				defaultPath: options.defaultPath,
			});

			if (result.canceled) {
				return null;
			}

			return result.filePath ?? null;
		}

		const properties: OpenDialogOptions["properties"] = [
			options?.directory ? "openDirectory" : "openFile",
			...(options?.multiple ? (["multiSelections"] as const) : []),
			...(options?.directory && options?.recursive ?
				(["createDirectory"] as const)
			:	[]),
		];

		const result = await dialog.showOpenDialog(getWindow(), {
			title: options?.title,
			properties,
			defaultPath: options?.defaultPath,
		});

		if (result.canceled) {
			return null;
		}

		if (options?.multiple) {
			return result.filePaths;
		}

		return result.filePaths[0] ?? null;
	},
);

ipcMain.handle("quadrant:open-url:listener-ready", (event) => {
	if (mainWindow && event.sender.id === mainWindow.webContents.id) {
		openUrlRendererReady = true;
		flushPendingDeepLinks();
	}
});

ipcMain.handle(
	"quadrant:shell:open-external",
	async (_event, payload: { url: string }) => {
		await shell.openExternal(payload.url);
	},
);

ipcMain.handle(
	"quadrant:shell:open-path",
	async (_event, payload: { targetPath: string }) => {
		const errorMessage = await shell.openPath(payload.targetPath);
		if (errorMessage) {
			throw new Error(errorMessage);
		}
	},
);

ipcMain.handle("quadrant:clipboard:read-text", async () =>
	clipboard.readText(),
);
ipcMain.handle(
	"quadrant:clipboard:write-text",
	async (_event, payload: { text: string }) => {
		clipboard.writeText(payload.text);
	},
);

ipcMain.handle("quadrant:platform", async () =>
	normalizeDesktopPlatform(process.platform),
);
ipcMain.handle("quadrant:app-version", async () => quadrantAppVersion);
ipcMain.handle(
	"quadrant:runtime-version",
	async () => process.versions.electron,
);

ipcMain.handle("quadrant:updater:check", async () => {
	await requestCheckForUpdates();
});

ipcMain.handle("quadrant:updater:install", async () => {
	if (!updateDownloaded) {
		throw new Error("No downloaded update is available");
	}
	autoUpdater.quitAndInstall();
});

ipcMain.handle("quadrant:updater:is-enabled", async () =>
	isAutoupdateEnabled(),
);

ipcMain.handle("quadrant:window:minimize", async () => {
	getWindow().minimize();
});

ipcMain.handle("quadrant:window:hide", async () => {
	getWindow().hide();
});

ipcMain.handle(
	"quadrant:window:set-enabled",
	async (_event, payload: { enabled: boolean }) => {
		getWindow().setEnabled(payload.enabled);
	},
);

ipcMain.handle("quadrant:window:set-focus", async () => {
	getWindow().focus();
});

ipcMain.handle("quadrant:window:unminimize", async () => {
	const window = getWindow();
	if (window.isMinimized()) {
		window.restore();
	}
});

ipcMain.handle(
	"quadrant:window:set-progress-bar",
	async (_event, payload: { state: WindowProgressState }) => {
		const window = getWindow();
		const normalizedProgress =
			(
				typeof payload.state.progress === "number" &&
				payload.state.progress <= 1
			) ?
				payload.state.progress
			:	payload.state.progress / 100;
		const progress = payload.state.status === "none" ? -1 : normalizedProgress;
		window.setProgressBar(progress);
	},
);

ipcMain.handle(
	"quadrant:oauth:start",
	async (_event, payload: { options?: OAuthStartOptions }) => {
		const responseHtml =
			payload.options?.response ??
			"<html><body><h1>You can return to Quadrant now.</h1></body></html>";
		const ports = payload.options?.ports ?? [
			4000, 4001, 4002, 4003, 4004, 4005,
		];

		for (const port of ports) {
			try {
				const server = http.createServer((request, response) => {
					const url = `http://127.0.0.1:${port}${request.url ?? "/"}`;
					broadcast("quadrant:oauth:url", url);
					response.writeHead(200, {
						"Content-Type": "text/html; charset=utf-8",
					});
					response.end(responseHtml);
				});

				await new Promise<void>((resolve, reject) => {
					server.once("error", reject);
					server.listen(port, "127.0.0.1", () => resolve());
				});

				oauthServers.set(port, server);
				return port;
			} catch (error) {
				console.warn(`Failed to bind OAuth server on ${port}`, error);
			}
		}

		throw new Error("No available OAuth callback port");
	},
);

ipcMain.handle(
	"quadrant:oauth:cancel",
	async (_event, payload: { port: number }) => {
		const server = oauthServers.get(payload.port);
		if (!server) {
			return;
		}

		await new Promise<void>((resolve, reject) => {
			server.close((error) => {
				if (error) {
					reject(error);
					return;
				}
				resolve();
			});
		});
		oauthServers.delete(payload.port);
	},
);
