import { useEffect, useState } from "react";
import { LocalModpack, SyncContext, SyncedModpack } from "../../../intefaces";
import { getModpacks, getSyncedModpacks } from "../../../tools";

import SyncedModpackComponent from "./SyncedModpack/SyncedModpack";
import { motion } from "motion/react";

export default function SyncPage() {
  const [modpacks, setModpacks] = useState<SyncedModpack[]>([]);
  const [localModpacks, setLocalModpacks] = useState<LocalModpack[]>([]);

  const fetchSyncedModpacks = async () => {
    const syncedModpacks = await getSyncedModpacks(true);
    const localModpacks = await getModpacks(true);
    syncedModpacks.sort((a, b) => b.last_synced - a.last_synced);
    setModpacks(syncedModpacks);
    setLocalModpacks(localModpacks);
  };

  useEffect(() => {
    fetchSyncedModpacks().catch(console.error);
  }, []);

  return (
    <SyncContext.Provider
      value={{ refreshSyncedModpacks: fetchSyncedModpacks }}
    >
      <motion.div
        initial={{ y: 500, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        className="items-center justify-center flex flex-col flex-1 w-full"
      >
        <div className="bg-slate-800 flex flex-1 flex-col  rounded-2xl w-[98%]  ">
          {modpacks.map((modpack) => {
            const localModpackResult = localModpacks.filter(
              (localModpack) => localModpack.name === modpack.name
            );
            let localModpack: LocalModpack | undefined = undefined;
            if (localModpackResult.length !== 0) {
              localModpack = localModpackResult[0];
            }
            return (
              <SyncedModpackComponent
                modpack={modpack}
                localModpack={localModpack}
                key={modpack.modpack_id}
              ></SyncedModpackComponent>
            );
          })}
        </div>
      </motion.div>
    </SyncContext.Provider>
  );
}
