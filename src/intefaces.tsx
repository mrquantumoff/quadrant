export interface IContentContext {
  changePage: (name: string) => void;
  changeContent: (component: Page) => void;
  back: () => void;
  setSnackbar: (newSnackBarState: SnackbarState) => void;
}

export interface LocalModpack {
  name: string;
  version: string;
  modLoader: ModLoader;
  isApplied: boolean;
  lastSynced: number;
  mods: LocalMod[];
}

export interface ModpackOwner {
  username: string;
  admin: boolean;
}

export interface SyncedModpack {
  name: string;
  modpack_id: string;
  minecraft_version: string;
  mod_loader: ModLoader;
  mods: string;
  owners: ModpackOwner[];
  last_synced: number;
}

export interface InstalledModpack {
  name: string;
  version: string;
  modLoader: ModLoader;
  mods: LocalMod[];
}

export enum ModSource {
  CurseForge = "ModSource.curseForge",
  Modrinth = "ModSource.modRinth",
  Online = "ModSource.online",
}

export interface LocalMod {
  id: string;
  downloadUrl: string;
  source: ModSource;
}

export interface Page {
  title: string;
  content: React.ReactNode;
  icon: React.ReactNode;
  name: string;
  style: string;
  main: boolean;
}

export enum ModType {
  Mod = "Mod",
  ResourcePack = "ResourcePack",
  ShaderPack = "Shader",
  Unknown = "Unknown",
}

export interface IMod {
  name: string;
  id: string;
  downloadCount: number;
  version: string;
  modType: ModType;
  source: ModSource;
  slug: string;
  thumbnailUrls: string[];
  url: string;
  description: string;
  license: string;
  modIconUrl: string;
  downloadable: boolean;
  showPreviousVersion: boolean;
  newVersion: UniversalModFile | null;
  deleteable: boolean;
  autoinstallable: boolean;
}

export interface UniversalModFile {
  id: string;
  fileName: string;
  downloadUrl: string;
  sha1: string;
  size: number;
}

export interface MinecraftVersion {
  version: string;
  versionType: string;
}

export interface GlobalSearchModsArgs {
  source: ModSource;
  query: string;
  modType: string;
  filterOn: boolean;
}

export interface GetModArgs {
  id: string;
  downloadable: boolean;
  showPreviousVersion: boolean;
  deletable: boolean;
  versionTarget: string;
  modLoader: ModLoader;
  modpack: string;
}

export enum ModLoader {
  Forge = "Forge",
  Fabric = "Fabric",
  NeoForge = "NeoForge",
  Rift = "Rift",
  Quilt = "Quilt",
  Unknown = "Unknown",
}

export interface ModProgress {
  modId: string;
  progress: number;
}
export interface SnackbarState {
  message: React.ReactNode;
  className: string;
  timeout: number;
}

export interface AccountInfo {
  id: string;
  name: string;
  email: string;
  quadrant_sync_limit: number;
  quadrant_share_limit: number;
  login: string;
  notifications: AccountNotification[];
}

export interface AccountNotification {
  notification_id: string;
  user_id: string;
  message: string;
  created_at: number;
  read: boolean;
}
