/** @format */

import { IMod, LocalMod, LocalModpack, ModType } from "./intefaces";

/**
 * The entry of `modpack` that is the same mod as `mod`, which an install
 * would replace.
 *
 * Slugs are compared as well as ids because the same mod obtained from the
 * other provider carries a different id, and installing it again would leave
 * two jars of one mod in the pack. Keep in step with `InstalledMod::is_same_mod`
 * in quadrant-core, which decides what an install replaces.
 */
export function findInstalledIn(
  mod: Pick<IMod, "id" | "source" | "slug" | "modType">,
  modpack: Pick<LocalModpack, "mods"> | undefined,
): LocalMod | undefined {
  if (mod.modType !== ModType.Mod || modpack === undefined) {
    return undefined;
  }
  const slug = mod.slug.trim().toLowerCase();
  return modpack.mods.find(
    (installed) =>
      installed.id === mod.id ||
      (installed.source !== mod.source &&
        slug !== "" &&
        (installed.slug ?? "").trim().toLowerCase() === slug),
  );
}

/** Whether `mod` already has a jar in `modpack`. */
export function isInstalledIn(
  ...args: Parameters<typeof findInstalledIn>
): boolean {
  return findInstalledIn(...args) !== undefined;
}
