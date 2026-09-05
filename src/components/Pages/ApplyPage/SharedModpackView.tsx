/** @format */

import { useContext, useEffect, useRef, useState } from "react";
import { IMod, InstalledModpack } from "../../../intefaces";
import CircularProgress from "../../core/CircularProgress";
import { useTranslation } from "react-i18next";
import Button from "../../core/Button";
import { getMod, installModpack } from "../../../tools";
import Mod from "../../shared/Mod";
import { ContentContext } from "../../../intefaces";
import { invoke, listen } from "../../../desktop";
import { MdArrowBack } from "react-icons/md";

export interface SharedModpackViewProps {
  modpack: InstalledModpack;
  syncTarget?: { syncedAt: number; modpackId: string };
}

export default function SharedModpackView({
  modpack,
  syncTarget,
}: SharedModpackViewProps) {
  const [mods, setMods] = useState<IMod[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const { t } = useTranslation();
  const [progress, setProgress] = useState(1);
  const modpackInstallRequestedRef = useRef(false);

  const context = useContext(ContentContext);

  const installRemoteModpack = async () => {
    if (progress !== 1 || modpackInstallRequestedRef.current) {
      return;
    }
    modpackInstallRequestedRef.current = true;
    try {
      await installModpack(modpack);
      if (syncTarget) {
        await invoke("set_modpack_sync_date", {
          time: syncTarget.syncedAt,
          modpack: modpack.name,
          modpackId: syncTarget.modpackId,
        });
      }
    } catch (e: any) {
      modpackInstallRequestedRef.current = false;
      setProgress(1);
      context.setSnackbar({
        className: "bg-red-700",
        message: t(e),
        timeout: 5000,
      });
    }
  };

  useEffect(() => {
    let isUnmounted = false;
    let unlisten: (() => void | Promise<void>) | null = null;

    const attachListener = async () => {
      unlisten = await listen("modpackDownloadProgress", (progress: any) => {
        if (isUnmounted) {
          return;
        }
        setProgress(progress.payload);
        if (progress.payload === 1 && modpackInstallRequestedRef.current) {
          modpackInstallRequestedRef.current = false;
          context.setSnackbar({
            className: "bg-emerald-600",
            message: t("downloadSuccess"),
            timeout: 5000,
          });
        }
      });

      if (isUnmounted && unlisten) {
        await unlisten();
        unlisten = null;
      }
    };

    attachListener().catch(console.error);

    return () => {
      isUnmounted = true;
      if (unlisten) {
        unlisten();
      }
    };
  }, [context, t]);

  useEffect(() => {
    const effect = async () => {
      setMods([]);
      setIsLoading(true);

      const fetchMods = async () => {
        for (const mod of modpack.mods) {
          try {
            const newMod = await getMod(
              {
                deletable: false,
                id: mod.id,
                downloadable: false,
                showPreviousVersion: false,
                versionTarget: "",
                modLoader: modpack.modLoader,
                modpack: modpack.name,
                selectable: false,
                selectUrl: null,
              },
              mod.source,
            );
            setMods((prevMods) => [...prevMods, newMod]);
          } catch (error) {
            console.error("Failed to fetch mod:", error);
          }
        }
        setIsLoading(false);
      };

      fetchMods().catch((error) => {
        console.error("Failed to load shared modpack", error);
        setIsLoading(false);
      });
    };
    effect().catch(console.error);
  }, [modpack]);

  return (
    <div className="flex flex-1 flex-col justify-center items-center w-full my-8 h-[80vh] ">
      <button
        onClick={() => context.back()}
        className="self-start flex items-center gap-1 text-sm font-bold text-slate-400 hover:text-slate-100 transition-colors cursor-pointer"
      >
        <MdArrowBack className="size-4.5" />
        {t("cancel")}
      </button>
      {isLoading && (
        <div className="bg-slate-800 rounded-4xl p-4">
          <CircularProgress />
        </div>
      )}
      {!isLoading && (
        <div className="bg-slate-800 p-4 flex flex-col rounded-4xl font-bold">
          <p>
            {modpack.name} | {modpack.modLoader} | {modpack.version} |{" "}
            {t("modCount", { amount: mods.length })}
          </p>
          <div className=" items-center justify-center my-4 rounded-4xl p-2 h-min  border-slate-900 border-8 ">
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4 mb-0 gap-4 p-4 max-h-[35vh] max-w-[80vw] overflow-auto  ">
              {mods.map((mod) => {
                return (
                  <Mod
                    key={mod.id}
                    mod={mod}
                    modpack={modpack.name}
                    className={"h-72 "}
                  />
                );
              })}
            </div>
          </div>
          <div className="flex w-full">
            <Button
              className={
                "mt-2 w-full mr-1 " +
                (progress === 1
                  ? "bg-emerald-600 hover:bg-emerald-700"
                  : "bg-slate-700 hover:bg-slate-700 cursor-not-allowed")
              }
              onClick={installRemoteModpack}
            >
              {progress === 1
                ? t("download")
                : (progress * 100).toFixed(2) + "%"}
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
