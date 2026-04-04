export interface QuadrantClientOptions {
  dataDir: string;
  mcFolder?: string | null;
  apiBaseUrl?: string | null;
  oauthClientId: string;
  oauthClientSecret: string;
  quadrantApiKey: string;
  configStoreName?: string | null;
  updateStoreName?: string | null;
  keyringServiceName?: string | null;
  appVersion?: string | null;
  osName?: string | null;
  userAgent?: string | null;
}

export interface QuadrantEventEnvelope {
  event: string;
  payload: unknown;
}

export interface QuadrantClient {
  startBackgroundWorkers(): Promise<void>;
  stopBackgroundWorkers(): Promise<void>;
  shutdown(): Promise<void>;
  initConfig(): Promise<void>;
  getMinecraftFolder(): Promise<string>;
  invoke(command: string, payload?: unknown): Promise<unknown>;
  getModpacks(hideFree?: boolean): Promise<unknown>;
  getAccountInfo(): Promise<unknown>;
  getNews(): Promise<unknown>;
  installMod(args: unknown): Promise<void>;
  syncModpack(modpack: unknown, overwrite?: boolean): Promise<void>;
  on(eventName: string, listener: (payload: unknown) => void): () => void;
  off(eventName: string, listener: (payload: unknown) => void): void;
  once(eventName: string, listener: (payload: unknown) => void): void;
}

export function createQuadrantClient(
  options: QuadrantClientOptions,
  nativeModule?: any,
): QuadrantClient;
