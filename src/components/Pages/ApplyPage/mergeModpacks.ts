/** @format */

import { LocalModpack, SyncedModpack } from "../../../intefaces";

/**
 * One row of the Apply page list. A modpack that is both installed locally
 * and synced to Quadrant Sync is a single entry carrying both records.
 */
export interface MergedModpack {
  local?: LocalModpack;
  synced?: SyncedModpack;
}

function matchesQuery(
  query: string,
  name: string,
  version: string,
  modLoader: string,
) {
  if (!query) {
    return true;
  }
  return (
    name.toLowerCase().includes(query) ||
    version.toLowerCase().includes(query) ||
    modLoader.toLowerCase().includes(query)
  );
}

function pairsWith(local: LocalModpack, synced: SyncedModpack) {
  if (local.modpackId) {
    return local.modpackId === synced.modpack_id;
  }
  return local.name === synced.name;
}

/**
 * Pairs every local modpack with its cloud counterpart (by modpack id, or by
 * name for packs that predate ids) and appends the cloud packs that are not
 * installed, newest sync first. `local` is expected to be pre-filtered by the
 * caller; the cloud list is filtered here against the same fields.
 */
export function mergeModpacks(
  local: LocalModpack[],
  synced: SyncedModpack[],
  searchQuery = "",
): MergedModpack[] {
  const claimed = new Set<string>();
  const rows: MergedModpack[] = local.map((modpack) => {
    const counterpart = synced.find(
      (candidate) =>
        !claimed.has(candidate.modpack_id) && pairsWith(modpack, candidate),
    );
    if (counterpart) {
      claimed.add(counterpart.modpack_id);
    }
    return { local: modpack, synced: counterpart };
  });

  const cloudOnly = synced
    .filter(
      (modpack) =>
        !claimed.has(modpack.modpack_id) &&
        matchesQuery(
          searchQuery,
          modpack.name,
          modpack.minecraft_version,
          modpack.mod_loader,
        ),
    )
    .sort((a, b) => b.last_synced - a.last_synced)
    .map((modpack) => ({ synced: modpack }));

  return [...rows, ...cloudOnly];
}
