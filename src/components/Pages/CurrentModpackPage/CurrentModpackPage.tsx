import { useEffect, useRef, useState } from "react";
import { getMinecraftFolder, getModpacks } from "../../../tools";
import { LocalModpack } from "../../../intefaces";
import ModpackView from "../../shared/Pages/ModpackView";
import { watch, type UnwatchFn } from "@tauri-apps/plugin-fs";
import * as path from "@tauri-apps/api/path";
import { motion } from "motion/react";

export default function CurrentModpackPage() {
  const [currentModpack, setCurrentModpack] = useState<LocalModpack>();
  const mountedRef = useRef(true);

  const updateModpack = async () => {
    const newModpack = (await getModpacks(false)).filter(
      (modpack) => modpack.isApplied
    )[0];
    if (!mountedRef.current) {
      return;
    }
    setCurrentModpack(newModpack);
  };

  useEffect(() => {
    mountedRef.current = true;
    const effect = async () => {
      const newModpack = (await getModpacks(false)).filter(
        (modpack) => modpack.isApplied
      )[0];

      if (mountedRef.current) {
        setCurrentModpack(newModpack);
      }

      const mcFolder = await path.join(await getMinecraftFolder(false), "mods");

      const unwatchMods = await watch(
        mcFolder,
        () => {
          if (mountedRef.current) {
            void updateModpack();
          }
        },
        {
          delayMs: 500,
        }
      );

      return unwatchMods;
    };

    let unwatch: UnwatchFn | undefined;
    effect()
      .then((result) => {
        if (result) {
          if (mountedRef.current) {
            unwatch = result;
          } else {
            result();
          }
        }
      })
      .catch((error) => console.error(error));

    return () => {
      mountedRef.current = false;
      if (unwatch) {
        unwatch();
      }
    };
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
            unknownMods={currentModpack.unknownMods}
          ></ModpackView>
        ) : (
          <div>-</div>
        )}
      </motion.div>
    </>
  );
}
