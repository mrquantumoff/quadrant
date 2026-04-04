import type {
  DesktopStoreAdapter,
  DesktopWindowAdapter,
  RuntimeAdapter,
  UnlistenFn,
} from "./contract";
import type {
  DesktopCommand,
  DesktopBackendEventEnvelope,
  DesktopOAuthStartOptions,
  DesktopStoreChangeEvent,
  DesktopWatchOptions,
  DesktopWindowProgressState,
} from "./types";

function getBridge() {
  if (!window.quadrantElectron) {
    throw new Error("Quadrant Electron bridge is unavailable");
  }
  return window.quadrantElectron;
}

function normalizeElectronInvokeError(error: unknown): string {
  const serializedMessage =
    typeof error === "object" &&
    error !== null &&
    "message" in error &&
    typeof (error as { message?: unknown }).message === "string"
      ? (error as { message: string }).message
      : null;

  const rawMessage =
    error instanceof Error
      ? error.message
      : serializedMessage !== null
        ? serializedMessage
        : typeof error === "string"
          ? error
          : String(error);

  const message = rawMessage
    .replace(/^Error occurred in handler for 'quadrant:invoke':\s*/, "")
    .trim();

  const nestedErrorMatch = message.match(
    /^\[Error:\s*([^[\]]+?)\](?:\s*\{.*\})?$/s,
  );
  if (nestedErrorMatch) {
    return nestedErrorMatch[1].trim();
  }

  const directErrorMatch = message.match(/^Error:\s*(.+)$/s);
  if (directErrorMatch) {
    return directErrorMatch[1].trim();
  }

  return message.replace(/\s*\{ code: .*$/s, "").trim();
}

class ElectronStoreAdapter implements DesktopStoreAdapter {
  constructor(private readonly storeName: string) {}

  async get<T>(key: string): Promise<T | undefined> {
    return getBridge().storeGet<T>(this.storeName, key);
  }

  async set(key: string, value: unknown): Promise<void> {
    await getBridge().storeSet(this.storeName, key, value);
  }

  async save(): Promise<void> {
    await getBridge().storeSave(this.storeName);
  }

  async onChange(listener: (key: string) => void): Promise<UnlistenFn> {
    return getBridge().addStoreChangeListener(
      (event: DesktopStoreChangeEvent) => {
        if (event.storeName === this.storeName) {
          listener(event.key);
        }
      },
    );
  }

  async onKeyChange<T>(
    key: string,
    listener: (value: T | null) => void,
  ): Promise<UnlistenFn> {
    return getBridge().addStoreChangeListener(
      (event: DesktopStoreChangeEvent) => {
        if (event.storeName === this.storeName && event.key === key) {
          listener((event.value as T | null | undefined) ?? null);
        }
      },
    );
  }
}

class ElectronWindowAdapter implements DesktopWindowAdapter {
  async minimize(): Promise<void> {
    await getBridge().windowMinimize();
  }

  async hide(): Promise<void> {
    await getBridge().windowHide();
  }

  async setEnabled(enabled: boolean): Promise<void> {
    await getBridge().windowSetEnabled(enabled);
  }

  async setFocus(): Promise<void> {
    await getBridge().windowSetFocus();
  }

  async unminimize(): Promise<void> {
    await getBridge().windowUnminimize();
  }

  async setProgressBar(state: DesktopWindowProgressState): Promise<void> {
    await getBridge().windowSetProgressBar(state);
  }
}

export const electronRuntime: RuntimeAdapter = {
  createStore(name: string) {
    return new ElectronStoreAdapter(name);
  },
  async invoke<T>(command: DesktopCommand, payload?: unknown) {
    try {
      return await getBridge().invoke<T>(command, payload);
    } catch (error) {
      throw normalizeElectronInvokeError(error);
    }
  },
  async listen<T = unknown>(
    event: string,
    listener: (event: DesktopBackendEventEnvelope<T>) => void,
  ) {
    return getBridge().addBackendEventListener((backendEvent) => {
      if (backendEvent.event === event) {
        listener(backendEvent as DesktopBackendEventEnvelope<T>);
      }
    });
  },
  async watch(
    targetPath: string,
    listener: () => void,
    options?: DesktopWatchOptions,
  ) {
    return getBridge().watchPath(targetPath, options, listener);
  },
  async joinPath(...segments: string[]) {
    return getBridge().joinPath(...segments);
  },
  async openDialog(options) {
    return getBridge().openDialog(options);
  },
  async openExternal(url: string) {
    await getBridge().openExternal(url);
  },
  async openPath(targetPath: string) {
    await getBridge().openPath(targetPath);
  },
  async readClipboardText() {
    return getBridge().readClipboardText();
  },
  async writeClipboardText(text: string) {
    await getBridge().writeClipboardText(text);
  },
  async platform() {
    return getBridge().platform();
  },
  async getRuntimeName() {
    return "Electron";
  },
  async getAppVersion() {
    return getBridge().getAppVersion();
  },
  async getRuntimeVersion() {
    return getBridge().getRuntimeVersion();
  },
  async requestCheckForUpdates() {
    await getBridge().requestCheckForUpdates();
  },
  async installUpdate() {
    await getBridge().installUpdate();
  },
  async isAutoupdateEnabled() {
    return getBridge().isAutoupdateEnabled();
  },
  getWindow() {
    return new ElectronWindowAdapter();
  },
  async onOpenUrl(listener) {
    return getBridge().addOpenUrlListener(listener);
  },
  async startOAuthServer(options: DesktopOAuthStartOptions) {
    return getBridge().startOAuthServer(options);
  },
  async cancelOAuthServer(port: number) {
    await getBridge().cancelOAuthServer(port);
  },
  async onOAuthUrl(listener) {
    return getBridge().addOAuthUrlListener(listener);
  },
  async fetch(input: string, init?: RequestInit) {
    return fetch(input, init);
  },
  isProductionBuild() {
    return import.meta.env.PROD;
  },
};
