/** @format */

import { ModLoader, ModSource } from "./intefaces";

export type ModLoaderProvider = ModSource.CurseForge | ModSource.Modrinth;

export interface ModLoaderOption {
  value: ModLoader;
  label: string;
  providers: ModLoaderProvider[];
}

const allLoaderProviders: ModLoaderProvider[] = [
  ModSource.CurseForge,
  ModSource.Modrinth,
];

// Shared source of truth for which loader options each provider can actually query.
export const MOD_LOADER_OPTIONS: ModLoaderOption[] = [
  {
    value: ModLoader.Fabric,
    label: "Fabric",
    providers: [ModSource.CurseForge, ModSource.Modrinth],
  },
  {
    value: ModLoader.Forge,
    label: "Forge",
    providers: [ModSource.CurseForge, ModSource.Modrinth],
  },
  {
    value: ModLoader.NeoForge,
    label: "NeoForge",
    providers: [ModSource.CurseForge, ModSource.Modrinth],
  },
  {
    value: ModLoader.Babric,
    label: "Babric",
    providers: [ModSource.Modrinth],
  },
  {
    value: ModLoader.BtaBabric,
    label: "BTA (Babric)",
    providers: [ModSource.Modrinth],
  },
  {
    value: ModLoader.JavaAgent,
    label: "Java Agent",
    providers: [ModSource.Modrinth],
  },
  {
    value: ModLoader.LegacyFabric,
    label: "Legacy Fabric",
    providers: [ModSource.Modrinth],
  },
  {
    value: ModLoader.LiteLoader,
    label: "LiteLoader",
    providers: [ModSource.CurseForge, ModSource.Modrinth],
  },
  {
    value: ModLoader.RisugamisModLoader,
    label: "Risugami's ModLoader",
    providers: [ModSource.Modrinth],
  },
  {
    value: ModLoader.NilLoader,
    label: "NilLoader",
    providers: [ModSource.Modrinth],
  },
  {
    value: ModLoader.Ornithe,
    label: "Ornithe",
    providers: [ModSource.Modrinth],
  },
  {
    value: ModLoader.Quilt,
    label: "Quilt",
    providers: [ModSource.CurseForge, ModSource.Modrinth],
  },
  {
    value: ModLoader.Rift,
    label: "Rift",
    providers: [ModSource.Modrinth],
  },
];

export function getModLoaderOptions(
  providers: ModLoaderProvider[] = allLoaderProviders,
): ModLoaderOption[] {
  const activeProviders =
    providers.length > 0 ? providers : allLoaderProviders;

  return MOD_LOADER_OPTIONS.filter((option) =>
    option.providers.some((provider) => activeProviders.includes(provider)),
  );
}

export function loaderProvidersFromSettings(
  curseForge: boolean | null | undefined,
  modrinth: boolean | null | undefined,
): ModLoaderProvider[] {
  const providers: ModLoaderProvider[] = [];

  if (curseForge) {
    providers.push(ModSource.CurseForge);
  }
  if (modrinth) {
    providers.push(ModSource.Modrinth);
  }

  return providers.length > 0 ? providers : allLoaderProviders;
}

export function loaderProvidersForSource(
  source: ModSource,
): ModLoaderProvider[] {
  if (source === ModSource.CurseForge) {
    return [ModSource.CurseForge];
  }
  if (source === ModSource.Modrinth) {
    return [ModSource.Modrinth];
  }

  return allLoaderProviders;
}

export function loaderSupportsProvider(
  loader: ModLoader | string,
  provider: ModLoaderProvider,
): boolean {
  // Unknown means "do not filter by loader", so every provider remains eligible.
  if (!loader || loader === ModLoader.Unknown) {
    return true;
  }

  return (
    MOD_LOADER_OPTIONS.find((option) => option.value === loader)?.providers.includes(
      provider,
    ) ?? false
  );
}
