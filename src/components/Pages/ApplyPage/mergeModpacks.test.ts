/** @format */

import { describe, expect, it } from "vitest";
import { LocalModpack, ModLoader, SyncedModpack } from "../../../intefaces";
import { mergeModpacks } from "./mergeModpacks";

function local(over: Partial<LocalModpack>): LocalModpack {
  return {
    name: "Pack",
    version: "1.20.1",
    modLoader: ModLoader.Fabric,
    isApplied: false,
    lastSynced: 0,
    mods: [],
    unknownMods: false,
    ...over,
  };
}

function synced(over: Partial<SyncedModpack>): SyncedModpack {
  return {
    name: "Pack",
    modpack_id: "id",
    minecraft_version: "1.20.1",
    mod_loader: ModLoader.Fabric,
    mods: "[]",
    owners: [],
    last_synced: 1,
    ...over,
  };
}

describe("mergeModpacks", () => {
  it("pairs a local modpack with its cloud record by modpack id", () => {
    const rows = mergeModpacks(
      [local({ name: "Renamed", modpackId: "abc" })],
      [synced({ name: "Original", modpack_id: "abc" })],
    );

    expect(rows).toHaveLength(1);
    expect(rows[0].local?.name).toBe("Renamed");
    expect(rows[0].synced?.modpack_id).toBe("abc");
  });

  it("falls back to the name only for local modpacks without an id", () => {
    const rows = mergeModpacks(
      [local({ name: "Legacy" }), local({ name: "Other", modpackId: "zzz" })],
      [synced({ name: "Legacy", modpack_id: "abc" }), synced({ name: "Other", modpack_id: "def" })],
    );

    expect(rows.map((row) => [row.local?.name, row.synced?.modpack_id])).toEqual([
      ["Legacy", "abc"],
      ["Other", undefined],
      [undefined, "def"],
    ]);
  });

  it("keeps local order and appends cloud-only packs newest first", () => {
    const rows = mergeModpacks(
      [local({ name: "B" }), local({ name: "A" })],
      [
        synced({ name: "Old", modpack_id: "1", last_synced: 10 }),
        synced({ name: "New", modpack_id: "2", last_synced: 20 }),
      ],
    );

    expect(rows.map((row) => row.local?.name ?? row.synced?.name)).toEqual([
      "B",
      "A",
      "New",
      "Old",
    ]);
  });

  it("filters cloud-only packs by name, version and loader like the local list", () => {
    const cloud = [
      synced({ name: "Alpha", modpack_id: "1" }),
      synced({ name: "Beta", modpack_id: "2", minecraft_version: "1.21" }),
      synced({ name: "Gamma", modpack_id: "3", mod_loader: ModLoader.Forge }),
    ];

    expect(mergeModpacks([], cloud, "alpha").map((r) => r.synced?.name)).toEqual(["Alpha"]);
    expect(mergeModpacks([], cloud, "1.21").map((r) => r.synced?.name)).toEqual(["Beta"]);
    expect(mergeModpacks([], cloud, "forge").map((r) => r.synced?.name)).toEqual(["Gamma"]);
  });

  it("does not let two local packs claim the same cloud record", () => {
    const rows = mergeModpacks(
      [local({ name: "Dup" }), local({ name: "Dup" })],
      [synced({ name: "Dup", modpack_id: "1" })],
    );

    expect(rows.filter((row) => row.synced).length).toBe(1);
  });
});
