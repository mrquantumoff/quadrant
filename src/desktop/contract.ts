import type {
  DesktopBackendEventEnvelope,
  DesktopCommand,
  DesktopDialogOptions,
  DesktopOAuthStartOptions,
  DesktopStoreChangeEvent,
  DesktopWatchOptions,
  DesktopWindowProgressState,
} from "./types";

export type UnlistenFn = () => void | Promise<void>;

export interface DesktopStoreAdapter {
  get<T>(key: string): Promise<T | undefined>;
  set(key: string, value: unknown): Promise<void>;
  save(): Promise<void>;
  onChange(listener: (key: string) => void): Promise<UnlistenFn>;
  onKeyChange<T>(key: string, listener: (value: T | null) => void): Promise<UnlistenFn>;
}

export interface DesktopWindowAdapter {
  minimize(): Promise<void>;
  hide(): Promise<void>;
  setEnabled(enabled: boolean): Promise<void>;
  setFocus(): Promise<void>;
  unminimize(): Promise<void>;
  setProgressBar(state: DesktopWindowProgressState): Promise<void>;
}

export interface RuntimeAdapter {
  createStore(name: string): DesktopStoreAdapter;
  invoke<T>(command: DesktopCommand, payload?: unknown): Promise<T>;
  listen<T = unknown>(
    event: string,
    listener: (event: DesktopBackendEventEnvelope<T>) => void,
  ): Promise<UnlistenFn>;
  watch(
    targetPath: string,
    listener: () => void,
    options?: DesktopWatchOptions,
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
  getWindow(): DesktopWindowAdapter;
  onOpenUrl(listener: (urls: string[]) => void): Promise<UnlistenFn>;
  startOAuthServer(options: DesktopOAuthStartOptions): Promise<number>;
  cancelOAuthServer(port: number): Promise<void>;
  onOAuthUrl(listener: (url: string) => void): Promise<UnlistenFn>;
  fetch(input: string, init?: RequestInit): Promise<Response>;
  isProductionBuild(): boolean;
}

export interface ElectronBridge {
  invoke<T>(command: DesktopCommand, payload?: unknown): Promise<T>;
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
