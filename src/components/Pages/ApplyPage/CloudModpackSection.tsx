/** @format */

import { useEffect, useState } from "react";
import {
  AccountInfo,
  LocalModpack,
  SyncContext,
  SyncedModpack,
} from "../../../intefaces";
import { getAccountInfo, getModpacks, getSyncedModpacks } from "../../../tools";
import { useTranslation } from "react-i18next";
import { motion } from "motion/react";
import { listen } from "../../../desktop";
import SyncedModpackComponent from "./SyncedModpack";

export interface CloudModpackSectionProps {
  searchQuery: string;
}

export default function CloudModpackSection({
  searchQuery,
}: CloudModpackSectionProps) {
  const { t } = useTranslation();
  const [accountInfo, setAccountInfo] = useState<AccountInfo | null>(null);
  const [modpacks, setModpacks] = useState<SyncedModpack[]>([]);
  const [localModpacks, setLocalModpacks] = useState<LocalModpack[]>([]);

  const fetchSyncedModpacks = async () => {
    const syncedModpacks = await getSyncedModpacks(true);
    // Unfiltered on purpose: the local list is only used to pair each cloud
    // card with its counterpart, so a search filter would blank out the dates.
    const localModpacks = await getModpacks(true);
    syncedModpacks.sort((a, b) => b.last_synced - a.last_synced);
    setModpacks(syncedModpacks);
    setLocalModpacks(localModpacks);
  };

  useEffect(() => {
    let isUnmounted = false;
    const cleanupFns: Array<() => void> = [];

    const effect = async () => {
      let info: AccountInfo;
      try {
        info = await getAccountInfo();
      } catch (error) {
        // Throws when signed out, which must render nothing.
        console.error(error);
        return;
      }
      if (isUnmounted || info.quadrant_sync_limit === 0) {
        return;
      }
      setAccountInfo(info);

      await fetchSyncedModpacks();

      const unlisten = await listen<string>("refreshSyncedModpacks", () => {
        if (isUnmounted) {
          return;
        }
        void fetchSyncedModpacks();
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

  if (accountInfo === null || accountInfo.quadrant_sync_limit === 0) {
    return null;
  }

  const visibleModpacks = modpacks.filter((modpack) =>
    modpack.name.toLowerCase().includes(searchQuery),
  );

  return (
    <SyncContext.Provider
      value={{ refreshSyncedModpacks: fetchSyncedModpacks }}
    >
      <h2 className="text-2xl font-extrabold mx-8 mt-4 mb-2">
        {t("cloudModpacks")}
      </h2>
      <motion.div
        initial={{ y: 24, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        className="items-center justify-center flex flex-col flex-1 w-full transform-gpu backface-hidden will-change-[transform,opacity]"
      >
        <div className="bg-slate-800 flex flex-1 flex-col rounded-4xl w-[98%]  ">
          {visibleModpacks.map((modpack) => {
            const localModpack =
              localModpacks.find(
                (candidate) => candidate.modpackId === modpack.modpack_id,
              ) ??
              localModpacks.find(
                (candidate) =>
                  !candidate.modpackId && candidate.name === modpack.name,
              );
            return (
              <SyncedModpackComponent
                modpack={modpack}
                localModpack={localModpack}
                accountInfo={accountInfo}
                key={modpack.modpack_id}
              ></SyncedModpackComponent>
            );
          })}
        </div>
      </motion.div>
    </SyncContext.Provider>
  );
}
