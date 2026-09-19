/** @format */

import { IMod, LocalModpack, ModType } from "./intefaces";

/**
 * Whether `mod` already has a jar in `modpack`.
 *
 * Slugs are compared as well as ids because the same mod obtained from the
 * other provider carries a different id, and installing it again would leave
 * two jars of one mod in the pack.
 */
export function isInstalledIn(
  mod: Pick<IMod, "id" | "source" | "slug" | "modType">,
  modpack: LocalModpack | undefined,
): boolean {
  if (mod.modType !== ModType.Mod || modpack === undefined) {
    return false;
  }
  const slug = mod.slug.trim().toLowerCase();
  return modpack.mods.some((installed) => {
    if (installed.source === mod.source && installed.id === mod.id) {
      return true;
    }
    const installedSlug = (installed.slug ?? "").trim().toLowerCase();
    return slug !== "" && installedSlug === slug;
  });
}
