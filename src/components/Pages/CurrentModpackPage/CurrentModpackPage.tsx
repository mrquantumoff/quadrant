import { useEffect, useState } from "react";
import { getMinecraftFolder, getModpacks } from "../../../tools";
import { LocalModpack } from "../../../intefaces";
import ModpackView from "../../shared/Pages/ModpackView";
import { watch } from "@tauri-apps/plugin-fs";
import * as path from "@tauri-apps/api/path";
import { motion } from "motion/react";

export default function CurrentModpackPage() {
  const [currentModpack, setCurrentModpack] = useState<LocalModpack>();

  const updateModpack = async () => {
    const newModpack = (await getModpacks(false)).filter(
      (modpack) => modpack.isApplied
    )[0];
    setCurrentModpack(newModpack);
  };

  useEffect(() => {
    const effect = async () => {
      const newModpack = (await getModpacks(false)).filter(
        (modpack) => modpack.isApplied
      )[0];
      console.log(newModpack);
      setCurrentModpack(newModpack);

      const mcFolder = await path.join(await getMinecraftFolder(false), "mods");

      await watch(
        mcFolder,
        () => {
          updateModpack();
        },
        {
          delayMs: 500,
        }
      );
    };

    effect();
  }, []);

  return (
    <>
      <motion.div
        initial={{ y: 500, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        exit={{ y: 5000 }}
      >
        {currentModpack !== undefined ? (
          <ModpackView
            isApplied={currentModpack.isApplied}
            lastSynced={currentModpack.lastSynced}
            modLoader={currentModpack.modLoader}
            mods={currentModpack.mods}
            name={currentModpack.name}
            version={currentModpack.version}
          ></ModpackView>
        ) : (
          <div>-</div>
        )}
      </motion.div>
    </>
  );
}
