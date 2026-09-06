/** @format */

import { useEffect, useRef, useState } from "react";
import { AccountInfo, SyncedModpack } from "../../../intefaces";
import { getAccountInfo, getSyncedModpacks } from "../../../tools";
import { listen } from "../../../desktop";

export interface SyncedModpacksState {
  /** Null while signed out or when the account has no Quadrant Sync quota. */
  accountInfo: AccountInfo | null;
  syncedModpacks: SyncedModpack[];
  refresh: () => Promise<void>;
}

/**
 * Loads the signed-in account once and keeps the Quadrant Sync modpack list
 * fresh, re-fetching whenever the backend raises `refreshSyncedModpacks`.
 * Signed-out users get an empty list and a null account.
 */
export function useSyncedModpacks(): SyncedModpacksState {
  const [accountInfo, setAccountInfo] = useState<AccountInfo | null>(null);
  const [syncedModpacks, setSyncedModpacks] = useState<SyncedModpack[]>([]);

  const requestRef = useRef(0);
  const refresh = async () => {
    const request = ++requestRef.current;
    try {
      const modpacks = await getSyncedModpacks(true);
      if (request === requestRef.current) setSyncedModpacks(modpacks);
    } catch (error) {
      console.error(error);
    }
  };

  useEffect(() => {
    let isUnmounted = false;
    const cleanupFns: Array<() => void> = [];

    const effect = async () => {
      let info: AccountInfo;
      try {
        info = await getAccountInfo();
      } catch (error) {
        // Throws when signed out, which must leave the list empty.
        console.error(error);
        return;
      }
      if (isUnmounted || info.quadrant_sync_limit === 0) {
        return;
      }
      setAccountInfo(info);

      // A transient fetch failure must not prevent subscribing to recovery events.
      void refresh();
      const unlisten = await listen<string>("refreshSyncedModpacks", () => {
        if (isUnmounted) {
          return;
        }
        void refresh();
      });
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

  return { accountInfo, syncedModpacks, refresh };
}
