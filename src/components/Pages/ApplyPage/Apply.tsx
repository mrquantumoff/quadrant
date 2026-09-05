/** @format */

import { useContext, useEffect, useRef, useState } from "react";
import { LocalModpack, MinecraftVersion, ModLoader } from "../../../intefaces";
import {
  applyModpack,
  createModpack,
  deleteModpack,
  getMinecraftFolder,
  getModpacks,
  getVersions,
  openModpacksFolder,
} from "../../../tools";
import { useTranslation } from "react-i18next";
import Button from "../../core/Button";
import { AnimatePresence, motion } from "motion/react";
import "./Apply.css";
import { MdCheck, MdClear, MdCreate, MdFolder } from "react-icons/md";
import { ContentContext } from "../../../intefaces";
import LocalModpackCard from "./LocalModpackCard";
import ModpackEditDialog from "./ModpackEditDialog";
import { createDesktopStore, joinPath, listen, watch } from "../../../desktop";
import {
  loaderProvidersFromSettings,
  ModLoaderProvider,
} from "../../../modLoaders";
export default function ApplyPage() {
  const [modpacks, setModpacks] = useState<LocalModpack[]>([]);

  const { t } = useTranslation();
  const [isUpdateDialogOpen, setIsUpdateDialogOpen] = useState(false);
  const [isDialogToCreate, setIsDialogToCreate] = useState(false);

  const [modpackToUpdate, setModpackToUpdate] = useState<LocalModpack>({
    version: "",
    name: "",
    mods: [],
    isApplied: false,
    lastSynced: 0,
    modLoader: ModLoader.Unknown,
    unknownMods: false,
  });
  const [defaultModpack, setDefaultModpack] = useState<LocalModpack>({
    name: "",
    version: "",
    modLoader: ModLoader.Unknown,
    isApplied: false,
    lastSynced: 0,
    mods: [],
    unknownMods: false,
  });
  const [originalModpackName, setOriginalModpackName] = useState("free");
  const [versions, setVersions] = useState<MinecraftVersion[]>([]);
  const [searchQuery, setSearchQuery] = useState<string>("");
  const searchQueryRef = useRef("");
  const [loaderProviders, setLoaderProviders] = useState<ModLoaderProvider[]>(
    loaderProvidersFromSettings(true, true),
  );
  const context = useContext(ContentContext);

  // Get the modpacks for the first time and listen for changes to the Minecraft folder from the backend
  useEffect(() => {
    let isUnmounted = false;
    const cleanupFns: Array<() => void> = [];

    const effect = async () => {
      const configStore = createDesktopStore("config.json");
      const [versions, availableModpacks, curseForgeEnabled, modrinthEnabled] =
        await Promise.all([
          getVersions(),
          getModpacks(),
          configStore.get<boolean>("curseforge"),
          configStore.get<boolean>("modrinth"),
        ]);
      if (isUnmounted) {
        return;
      }
      setModpacks(availableModpacks);
      setVersions(versions);
      setLoaderProviders(
        loaderProvidersFromSettings(curseForgeEnabled, modrinthEnabled),
      );

      setDefaultModpack({
        name: "",
        version: versions[0]?.version ?? "",
        modLoader: ModLoader.Unknown,
        isApplied: false,
        lastSynced: 0,
        mods: [],
        unknownMods: false,
      });

      const unwatch = await watch(
        await joinPath(await getMinecraftFolder(false)),
        async () => {
          if (!isUnmounted) {
            await updateModpacks();
          }
        },
        {
          delayMs: 50,
        },
      );
      if (isUnmounted) {
        unwatch();
      } else {
        cleanupFns.push(unwatch);
      }

      const unlisten = await listen(
        "quadrantShareSubmission",
        async (event: any) => {
          const usesLeft = event.payload.uses_left;
          if (isUnmounted) {
            return;
          }
          context.setSnackbar({
            message: (
              <span className="flex">
                <MdCheck className="w-5 h-5 mx-2" />
                {t("copiedToClipboard", { amount: usesLeft })}
              </span>
            ),
            className: "bg-emerald-600 rounded-4xl",
            timeout: 5000,
          });
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

  useEffect(() => {
    const effect = async () => {
      await updateModpacks();
    };
    effect();
  }, [searchQuery]);

  const updateModpacks = async () => {
    const newModpacks = await getModpacks(true, searchQueryRef.current);

    setModpacks(newModpacks);
  };

  return (
    <>
      <motion.div
        initial={{ y: 24, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        exit={{ y: 24, opacity: 0 }}
        className="flex flex-1 flex-col w-full transform-gpu backface-hidden will-change-[transform,opacity]"
      >
        <input
          placeholder={t("search")}
          className="p-2 input w-[95.5%] bg-slate-700 h-11 rounded-full self-center mx-8 my-4 text-center"
          onChange={(event) => {
            const query = event.target.value.toLowerCase().trim();
            searchQueryRef.current = query;
            setSearchQuery(query);
          }}
          autoComplete="off"
          value={searchQuery}
        ></input>
        <div className="flex flex-row flex-wrap justify-center w-fit self-center bg-slate-700 rounded-4xl my-2 p-1.5">
          <Button
            onClick={() => {
              setIsDialogToCreate(true);
              setIsUpdateDialogOpen(true);
              setModpackToUpdate(defaultModpack);
            }}
            className="bg-emerald-600 mx-2 flex items-center align-middle w-fit hover:bg-emerald-700 px-4 rounded-4xl "
          >
            {t("createModpack")}
            <MdCreate className="w-5 h-5 mx-2" />
          </Button>
          <Button
            onClick={async () => {
              const firstVersion = versions[0]?.version;
              if (!firstVersion) {
                return;
              }
              try {
                await deleteModpack("free");
              } catch {
                // Ignore missing temporary modpack.
              }
              await createModpack("free", firstVersion, ModLoader.Unknown);
              await applyModpack("free");
              await updateModpacks();
            }}
            className="bg-slate-800 flex items-center align-middle mx-2 w-fit hover:bg-red-700 px-4 rounded-4xl "
          >
            {t("clear")}
            <MdClear className="w-5 h-5 mx-2" />
          </Button>
          <Button
            onClick={async () => {
              await openModpacksFolder();
            }}
            className="bg-slate-800 flex items-center align-middle mx-2 w-fit hover:bg-slate-700 px-4 rounded-4xl "
          >
            {t("openModpacksFolder")}
            <MdFolder className="w-5 h-5 mx-2" />
          </Button>
        </div>
        <div className="bg-slate-800 rounded-4xl mx-6 mb-8">
          <AnimatePresence>
            {modpacks?.map((modpack, index) => (
              <LocalModpackCard
                key={index}
                modpack={modpack}
                onChanged={updateModpacks}
                onEdit={(target) => {
                  setIsUpdateDialogOpen(true);
                  setIsDialogToCreate(false);
                  setOriginalModpackName(
                    JSON.parse(JSON.stringify(target.name)),
                  );
                  setModpackToUpdate(target);
                }}
              />
            ))}
          </AnimatePresence>
        </div>
        <ModpackEditDialog
          open={isUpdateDialogOpen}
          onClose={() => setIsUpdateDialogOpen(false)}
          isCreate={isDialogToCreate}
          versions={versions}
          loaderProviders={loaderProviders}
          initial={modpackToUpdate}
          originalName={originalModpackName}
          onSaved={updateModpacks}
        />
        <div className="h-1"></div>
      </motion.div>
    </>
  );
}
