/** @format */

import { useEffect, useRef, useState } from "react";
import { AccountInfo, SyncedModpack } from "../../../intefaces";
import { getSyncedModpacks } from "../../../tools";
import { listen } from "../../../desktop";
import { AccountState, readAccountState } from "../../../accountState";

/**
 * Whether the Quadrant Sync section has anything to show. `off` covers both a
 * signed-out user and an account with no Sync quota.
 */
export type CloudStatus =
  | { status: "loading" }
  | { status: "off" }
  | { status: "unreachable"; error: unknown }
  | { status: "ready" };

export interface SyncedModpacksState {
  status: CloudStatus;
  /** Null unless signed in with a Quadrant Sync quota. */
  accountInfo: AccountInfo | null;
  /** The last list that loaded; kept while the cloud is unreachable. */
  syncedModpacks: SyncedModpack[];
  /** Re-reads one modpack, or the whole list when given no id. */
  refresh: (modpackId?: string) => Promise<void>;
  /** Re-reads the account and then the whole list. */
  retry: () => Promise<void>;
}

function syncAccount(account: AccountState): AccountInfo | null {
  return account.status === "signedIn" && account.info.quadrant_sync_limit > 0
    ? account.info
    : null;
}

function cloudStatus(
  account: AccountState,
  listFailure: { error: unknown } | null,
): CloudStatus {
  switch (account.status) {
    case "loading":
    case "unreachable":
      return account;
    case "signedOut":
      return { status: "off" };
    case "signedIn":
      if (syncAccount(account) === null) {
        return { status: "off" };
      }
      return listFailure === null
        ? { status: "ready" }
        : { status: "unreachable", error: listFailure.error };
  }
}

/**
 * Folds a single-modpack fetch into the list. An empty result means the pack
 * is no longer ours in the cloud: deleted, or this account was kicked or left.
 */
function withRefreshedModpack(
  current: SyncedModpack[],
  modpackId: string,
  fetched: SyncedModpack[],
): SyncedModpack[] {
  const updated = fetched.find((modpack) => modpack.modpack_id === modpackId);
  if (updated === undefined) {
    return current.filter((modpack) => modpack.modpack_id !== modpackId);
  }
  if (!current.some((modpack) => modpack.modpack_id === modpackId)) {
    return [...current, updated];
  }
  return current.map((modpack) =>
    modpack.modpack_id === modpackId ? updated : modpack,
  );
}

/**
 * Loads the account and keeps the Quadrant Sync modpack list fresh,
 * re-fetching whenever the backend raises `refreshSyncedModpacks`. While the
 * server is unreachable the event, or `retry`, starts over from the account.
 */
export function useSyncedModpacks(): SyncedModpacksState {
  const [account, setAccount] = useState<AccountState>({ status: "loading" });
  const [listFailure, setListFailure] = useState<{ error: unknown } | null>(
    null,
  );
  const [syncedModpacks, setSyncedModpacks] = useState<SyncedModpack[]>([]);
  // Read by the event listener, which outlives the render that created it.
  const syncAccountRef = useRef<AccountInfo | null>(null);

  // Full reads are ordered by `requestRef`; a targeted read is ordered only
  // against reads of the same pack, and is dropped by any later full read.
  const requestRef = useRef(0);
  const pendingFullRef = useRef(0);
  const targetedRef = useRef(new Map<string, number>());
  const refresh = async (modpackId?: string) => {
    // A full read already in flight may predate this pack's change, and
    // patching around it would lose either the list or the change.
    const targetId = pendingFullRef.current > 0 ? undefined : modpackId;
    const request = targetId ? requestRef.current : ++requestRef.current;
    const targeted = targetId
      ? (targetedRef.current.get(targetId) ?? 0) + 1
      : 0;
    if (targetId) {
      targetedRef.current.set(targetId, targeted);
    } else {
      pendingFullRef.current++;
    }
    const isCurrent = () =>
      request === requestRef.current &&
      (!targetId || targetedRef.current.get(targetId) === targeted);
    try {
      const modpacks = await getSyncedModpacks(true, targetId);
      if (!isCurrent()) {
        return;
      }
      setSyncedModpacks((current) =>
        targetId ? withRefreshedModpack(current, targetId, modpacks) : modpacks,
      );
      // Only a full read proves the whole list is current again.
      if (!targetId) {
        setListFailure(null);
      }
    } catch (error) {
      console.error(error);
      if (isCurrent()) {
        setListFailure({ error });
      }
    } finally {
      if (!targetId) {
        pendingFullRef.current--;
      }
    }
  };

  const accountRequestRef = useRef(0);
  const load = async () => {
    const request = ++accountRequestRef.current;
    const next = await readAccountState();
    if (request !== accountRequestRef.current) {
      return;
    }
    setAccount(next);
    syncAccountRef.current = syncAccount(next);
    if (syncAccountRef.current === null) {
      // Drops any list read still in flight for a session that is gone.
      requestRef.current++;
      if (next.status !== "unreachable") {
        setSyncedModpacks([]);
      }
      return;
    }
    // Not awaited: a slow list read must not hold up subscribing to events.
    void refresh();
  };

  useEffect(() => {
    let isUnmounted = false;
    const cleanupFns: Array<() => void> = [];

    const effect = async () => {
      await load();
      if (isUnmounted) {
        return;
      }
      const unlisten = await listen<string | null>(
        "refreshSyncedModpacks",
        (event) => {
          if (isUnmounted) {
            return;
          }
          if (syncAccountRef.current === null) {
            void load();
            return;
          }
          // The host sends an empty payload when it cannot name the pack.
          void refresh(event.payload || undefined);
        },
      );
      if (isUnmounted) {
        unlisten();
      } else {
        cleanupFns.push(unlisten);
      }
    };

    effect().catch(console.error);

    return () => {
      isUnmounted = true;
      requestRef.current++;
      accountRequestRef.current++;
      while (cleanupFns.length > 0) {
        const cleanup = cleanupFns.pop();
        try {
          cleanup?.();
        } catch (error) {
          console.error(error);
        }
      }
    };
  }, []);

  return {
    status: cloudStatus(account, listFailure),
    accountInfo: syncAccount(account),
    syncedModpacks,
    refresh,
    retry: load,
  };
}
