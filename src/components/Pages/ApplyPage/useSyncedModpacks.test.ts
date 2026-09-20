/** @format */

import { beforeEach, describe, expect, it, vi } from "vitest";
import { act, renderHook, waitFor } from "@testing-library/react";
import { ModLoader, type SyncedModpack } from "../../../intefaces";

const getAccountInfo = vi.fn();
const getSyncedModpacks = vi.fn();
const listen = vi.fn();

vi.mock("../../../tools", () => ({
  getAccountInfo: (...a: unknown[]) => getAccountInfo(...a),
  getSyncedModpacks: (...a: unknown[]) => getSyncedModpacks(...a),
}));

vi.mock("../../../desktop", () => ({
  listen: (...a: unknown[]) => listen(...a),
}));

import { useSyncedModpacks } from "./useSyncedModpacks";

function cloudPack(over: Partial<SyncedModpack>): SyncedModpack {
  return {
    name: "Pack",
    modpack_id: "id",
    minecraft_version: "1.20.1",
    mod_loader: ModLoader.Fabric,
    mods: "[]",
    owners: [{ username: "me", admin: true }],
    last_synced: 1,
    ...over,
  };
}

// Raises the backend event by hand, with the modpack id the host would send.
let emit: ((payload: string | null) => void) | undefined;

beforeEach(() => {
  vi.clearAllMocks();
  emit = undefined;
  getAccountInfo.mockResolvedValue({ login: "me", quadrant_sync_limit: 5 });
  getSyncedModpacks.mockResolvedValue([]);
  listen.mockImplementation(
    async (
      event: string,
      cb: (e: { payload: unknown; event: string }) => void,
    ) => {
      if (event === "refreshSyncedModpacks") {
        emit = (payload) => cb({ payload, event });
      }
      return () => {};
    },
  );
});

async function renderLoaded(initial: SyncedModpack[]) {
  getSyncedModpacks.mockResolvedValue(initial);
  const view = renderHook(() => useSyncedModpacks());
  await waitFor(() =>
    expect(view.result.current.syncedModpacks).toEqual(initial),
  );
  await waitFor(() => expect(emit).toBeTypeOf("function"));
  return view;
}

function ids(packs: SyncedModpack[]) {
  return packs.map((pack) => pack.modpack_id);
}

describe("useSyncedModpacks", () => {
  it("re-reads only the named modpack and replaces it in place", async () => {
    const view = await renderLoaded([
      cloudPack({ modpack_id: "a", name: "Alpha" }),
      cloudPack({ modpack_id: "b", name: "Beta" }),
    ]);

    getSyncedModpacks.mockResolvedValue([
      cloudPack({ modpack_id: "a", name: "Alpha", last_synced: 99 }),
    ]);
    await act(async () => emit?.("a"));

    expect(getSyncedModpacks).toHaveBeenLastCalledWith(true, "a");
    expect(view.result.current.syncedModpacks).toEqual([
      cloudPack({ modpack_id: "a", name: "Alpha", last_synced: 99 }),
      cloudPack({ modpack_id: "b", name: "Beta" }),
    ]);
  });

  it("adds a modpack the list has never seen", async () => {
    const view = await renderLoaded([
      cloudPack({ modpack_id: "a", name: "Alpha" }),
    ]);

    getSyncedModpacks.mockResolvedValue([
      cloudPack({ modpack_id: "b", name: "Beta" }),
    ]);
    await act(async () => emit?.("b"));

    expect(ids(view.result.current.syncedModpacks)).toEqual(["a", "b"]);
  });

  // An empty answer for one id is how a deletion, a kick or a leave arrives.
  it("drops the modpack when the cloud no longer returns it", async () => {
    const view = await renderLoaded([
      cloudPack({ modpack_id: "a", name: "Alpha" }),
      cloudPack({ modpack_id: "b", name: "Beta" }),
    ]);

    getSyncedModpacks.mockResolvedValue([]);
    await act(async () => emit?.("a"));

    expect(ids(view.result.current.syncedModpacks)).toEqual(["b"]);
  });

  it.each([["" as string | null], [null]])(
    "re-reads the whole list for the %o payload",
    async (payload) => {
      const view = await renderLoaded([
        cloudPack({ modpack_id: "a", name: "Alpha" }),
      ]);

      getSyncedModpacks.mockResolvedValue([
        cloudPack({ modpack_id: "c", name: "Gamma" }),
      ]);
      await act(async () => emit?.(payload));

      expect(getSyncedModpacks).toHaveBeenLastCalledWith(true, undefined);
      expect(ids(view.result.current.syncedModpacks)).toEqual(["c"]);
    },
  );

  it("does not let an older full refresh undo a newer single-pack one", async () => {
    const view = await renderLoaded([
      cloudPack({ modpack_id: "a", name: "Alpha" }),
    ]);

    let resolveFull!: (packs: SyncedModpack[]) => void;
    getSyncedModpacks.mockReturnValueOnce(
      new Promise((resolve) => {
        resolveFull = resolve;
      }),
    );
    await act(async () => emit?.(""));

    getSyncedModpacks.mockResolvedValue([
      cloudPack({ modpack_id: "a", name: "Renamed" }),
    ]);
    await act(async () => emit?.("a"));
    await act(async () =>
      resolveFull([cloudPack({ modpack_id: "z", name: "Stale" })]),
    );

    expect(view.result.current.syncedModpacks).toEqual([
      cloudPack({ modpack_id: "a", name: "Renamed" }),
    ]);
  });

  it("re-reads the whole list when a pack changes during a full read", async () => {
    const view = await renderLoaded([]);

    let resolveFull!: (packs: SyncedModpack[]) => void;
    getSyncedModpacks.mockReturnValueOnce(
      new Promise((resolve) => {
        resolveFull = resolve;
      }),
    );
    await act(async () => emit?.(""));

    const both = [
      cloudPack({ modpack_id: "a", name: "Renamed" }),
      cloudPack({ modpack_id: "b" }),
    ];
    getSyncedModpacks.mockResolvedValue(both);
    await act(async () => emit?.("a"));
    expect(getSyncedModpacks).toHaveBeenLastCalledWith(true, undefined);
    await act(async () => resolveFull([cloudPack({ modpack_id: "a" })]));

    expect(view.result.current.syncedModpacks).toEqual(both);
  });

  it("applies overlapping refreshes of different modpacks", async () => {
    const view = await renderLoaded([
      cloudPack({ modpack_id: "a" }),
      cloudPack({ modpack_id: "b" }),
    ]);

    let resolveA!: (packs: SyncedModpack[]) => void;
    getSyncedModpacks.mockReturnValueOnce(
      new Promise((resolve) => {
        resolveA = resolve;
      }),
    );
    await act(async () => emit?.("a"));
    getSyncedModpacks.mockResolvedValueOnce([
      cloudPack({ modpack_id: "b", name: "New B" }),
    ]);
    await act(async () => emit?.("b"));
    await act(async () =>
      resolveA([cloudPack({ modpack_id: "a", name: "New A" })]),
    );

    expect(view.result.current.syncedModpacks).toEqual([
      cloudPack({ modpack_id: "a", name: "New A" }),
      cloudPack({ modpack_id: "b", name: "New B" }),
    ]);
  });
});
