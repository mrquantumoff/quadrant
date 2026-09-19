/** @format */

import { IMod, LocalModpack, ModType } from "./intefaces";

/**
 * Whether `mod` already has a jar in `modpack`.
 *
 * Slugs are compared as well as ids because the same mod obtained from the
 * other provider carries a different id, and installing it again would leave
 * two jars of one mod in the pack. Keep in step with `InstalledMod::is_same_mod`
 * in quadrant-core, which decides what an install replaces.
 */
export function isInstalledIn(
  mod: Pick<IMod, "id" | "source" | "slug" | "modType">,
  modpack: Pick<LocalModpack, "mods"> | undefined,
): boolean {
  if (mod.modType !== ModType.Mod || modpack === undefined) {
    return false;
  }
  const slug = mod.slug.trim().toLowerCase();
  return modpack.mods.some(
    (installed) =>
      installed.id === mod.id ||
      (installed.source !== mod.source &&
        slug !== "" &&
        (installed.slug ?? "").trim().toLowerCase() === slug),
  );
}
