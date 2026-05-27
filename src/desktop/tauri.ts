import { invoke as tauriInvoke } from "@tauri-apps/api/core";
import { listen as tauriListen } from "@tauri-apps/api/event";
import { getVersion, getTauriVersion } from "@tauri-apps/api/app";
import {
  getCurrentWindow,
  ProgressBarStatus as TauriProgressBarStatus,
} from "@tauri-apps/api/window";
import { join as tauriJoin } from "@tauri-apps/api/path";
import {
  open as openDialog,
  save as saveDialog,
} from "@tauri-apps/plugin-dialog";
import { watch as watchPath } from "@tauri-apps/plugin-fs";
import { fetch as tauriFetch } from "@tauri-apps/plugin-http";
import { getCurrent, onOpenUrl } from "@tauri-apps/plugin-deep-link";
import { platform as tauriPlatform } from "@tauri-apps/plugin-os";
import { LazyStore } from "@tauri-apps/plugin-store";
import { readText, writeText } from "@tauri-apps/plugin-clipboard-manager";
import { openPath, openUrl } from "@tauri-apps/plugin-opener";
import {
  cancel as cancelOAuthServer,
  onUrl as onOAuthUrl,
  start as startOAuthServer,
} from "@fabianlars/tauri-plugin-oauth";
import type { Event } from "@tauri-apps/api/event";
import type {
  RuntimeAdapter,
  DesktopStoreAdapter,
  DesktopWindowAdapter,
} from "./contract";
import type {
  DesktopCommand,
  DesktopOAuthStartOptions,
  DesktopWindowProgressState,
  ProgressBarStatusValue,
} from "./types";

function mapProgressStatus(
  status: ProgressBarStatusValue | undefined,
): TauriProgressBarStatus | undefined {
  switch (status) {
    case "none":
      return TauriProgressBarStatus.None;
    case "error":
      return TauriProgressBarStatus.Error;
    case "paused":
      return TauriProgressBarStatus.Paused;
    case "indeterminate":
      return TauriProgressBarStatus.Indeterminate;
    case "normal":
    default:
      return TauriProgressBarStatus.Normal;
  }
}

class TauriStoreAdapter implements DesktopStoreAdapter {
  private readonly store: LazyStore;

  constructor(name: string) {
    this.store = new LazyStore(name);
  }

  async get<T>(key: string): Promise<T | undefined> {
    return this.store.get<T>(key);
  }

  async set(key: string, value: unknown): Promise<void> {
    await this.store.set(key, value);
  }

  async save(): Promise<void> {
    await this.store.save();
  }

  async onChange(listener: (key: string) => void) {
    return this.store.onChange(listener);
  }

  async onKeyChange<T>(key: string, listener: (value: T | null) => void) {
    return this.store.onKeyChange<T>(key, (value) => listener(value ?? null));
  }
}

class TauriWindowAdapter implements DesktopWindowAdapter {
  private readonly window = getCurrentWindow();

  async minimize(): Promise<void> {
    await this.window.minimize();
  }

  async hide(): Promise<void> {
    await this.window.hide();
  }

  async setEnabled(enabled: boolean): Promise<void> {
    await this.window.setEnabled(enabled);
  }

  async setFocus(): Promise<void> {
    await this.window.setFocus();
  }

  async unminimize(): Promise<void> {
    await this.window.unminimize();
  }

  async setProgressBar(state: DesktopWindowProgressState): Promise<void> {
    await this.window.setProgressBar({
      progress: state.progress,
      status: mapProgressStatus(state.status),
    });
  }
}

export const tauriRuntime: RuntimeAdapter = {
  createStore(name: string) {
    return new TauriStoreAdapter(name);
  },
  async invoke<T>(command: DesktopCommand, payload?: unknown) {
    return tauriInvoke<T>(
      command,
      payload as Record<string, unknown> | undefined,
    );
  },
  async listen<T = unknown>(
    event: string,
    listener: (event: Event<T>) => void,
  ) {
    return tauriListen<T>(event, listener);
  },
  async watch(targetPath: string, listener, options) {
    return watchPath(targetPath, listener, options);
  },
  async joinPath(...segments: string[]) {
    return tauriJoin(...segments);
  },
  async openDialog(options) {
    if (options?.mode === "save") {
      return saveDialog({
        title: options.title,
        defaultPath: options.defaultPath,
      });
    }

    return openDialog({
      multiple: options?.multiple,
      directory: options?.directory,
      recursive: options?.recursive,
      title: options?.title,
      defaultPath: options?.defaultPath,
    });
  },
  async openExternal(url: string) {
    await openUrl(url);
  },
  async openPath(targetPath: string) {
    await openPath(targetPath);
  },
  async readClipboardText() {
    return readText();
  },
  async writeClipboardText(text: string) {
    await writeText(text);
  },
  async platform() {
    return tauriPlatform();
  },
  async getRuntimeName() {
    return "Tauri";
  },
  async getAppVersion() {
    return getVersion();
  },
  async getRuntimeVersion() {
    return getTauriVersion();
  },
  async requestCheckForUpdates() {
    await tauriInvoke("request_check_for_updates");
  },
  async installUpdate() {
    await tauriInvoke("install_update");
  },
  async isAutoupdateEnabled() {
    return tauriInvoke<boolean>("is_autoupdate_enabled");
  },
  getWindow() {
    return new TauriWindowAdapter();
  },
  async onOpenUrl(listener) {
    const currentUrls = await getCurrent();
    if (currentUrls && currentUrls.length > 0) {
      listener(currentUrls);
    }
    return onOpenUrl(listener);
  },
  async startOAuthServer(options: DesktopOAuthStartOptions) {
    return startOAuthServer(options);
  },
  async cancelOAuthServer(port: number) {
    await cancelOAuthServer(port);
  },
  async onOAuthUrl(listener) {
    return onOAuthUrl(listener);
  },
  async fetch(input: string, init?: RequestInit) {
    return tauriFetch(input, init);
  },
  isProductionBuild() {
    return import.meta.env.PROD;
  },
};
