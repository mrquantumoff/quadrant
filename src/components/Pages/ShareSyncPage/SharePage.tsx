/** @format */

import { useContext, useEffect, useRef, useState } from "react";
import { IMod, InstalledModpack } from "../../../intefaces";
import CircularProgress from "../../core/CircularProgress";
import { useTranslation } from "react-i18next";
import { Input } from "@headlessui/react";
import Button from "../../core/Button";
import {
  getMod,
  getQuadrantShareModpack,
  installModpack,
} from "../../../tools";
import Mod from "../../shared/Mod";
import { ContentContext } from "../../../intefaces";
import { invoke, listen, readClipboardText } from "../../../desktop";

export interface SharePageProps {
  preselectedModpack: InstalledModpack | undefined;
  modpackSync: number | null;
  modpackId: string | null;
}

export default function SharePage({
  preselectedModpack,
  modpackSync,
  modpackId,
}: SharePageProps) {
  const [modpack, setModpack] = useState<InstalledModpack | undefined>(
    undefined,
  );
  const [mods, setMods] = useState<IMod[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const { t } = useTranslation();
  const [code, setCode] = useState("");
  const [progress, setProgress] = useState(1);
  const modpackInstallRequestedRef = useRef(false);

  const extractCode = (input: string): string | null => {
    const trimmed = input.trim();
    if (/^\d{7}$/.test(trimmed)) {
      return trimmed;
    }
    try {
      const url = new URL(trimmed);
      if (
        url.hostname === "usequadrant.dev" ||
        url.hostname === "www.usequadrant.dev"
      ) {
        const match = url.pathname.match(/^\/modpack\/(\d{7})\/?$/);
        if (match) {
          return match[1];
        }
      }
    } catch {
      // not a URL
    }
    return null;
  };

  const getModpack = async () => {
    const extracted = extractCode(code);
    if (!extracted) {
      console.log("Code is not valid");
      return;
    }

    const newModpack = await getQuadrantShareModpack(extracted);
    console.log("New modpack: " + newModpack);
    setModpack(newModpack);
  };

  const installRemoteModpack = async () => {
    if (progress !== 1 || modpackInstallRequestedRef.current) {
      return;
    }
    modpackInstallRequestedRef.current = true;
    try {
      await installModpack(modpack!);
      if (modpackSync) {
        await invoke("set_modpack_sync_date", {
          time: modpackSync,
          modpack: modpack!.name,
          modpackId: modpackId,
        });
      }
    } catch (e: any) {
      modpackInstallRequestedRef.current = false;
      context.setSnackbar({
        className: "bg-red-700",
        message: t(e),
        timeout: 5000,
      });
    }
  };

  const context = useContext(ContentContext);

  useEffect(() => {
    console.log("Mods count: " + mods.length);
  }, [mods]);

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
    if (preselectedModpack !== undefined) {
      setModpack(preselectedModpack);
    }
  }, [preselectedModpack]);

  useEffect(() => {
    const effect = async () => {
      if (modpack === undefined) {
        setMods([]);
        return;
      }
      setMods([]);

      const fetchMods = async () => {
        console.log("Mods: " + modpack.mods.length);

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

      fetchMods();
    };
    effect().catch(console.error);
  }, [modpack]);

  return (
    <div className="flex flex-1 flex-col justify-center items-center w-full my-8 h-[80vh] ">
      {isLoading && (
        <div className="bg-slate-800 rounded-4xl p-4">
          <CircularProgress />
        </div>
      )}
      {!isLoading && (
        <>
          <div className="bg-slate-800 p-4 flex flex-col rounded-4xl font-bold">
            {modpack === undefined && (
              <>
                <p>{t("manualInput")}</p>
                <Input
                  className="input mt-8"
                  placeholder={t("manualInput")}
                  value={code}
                  onChange={(e) => {
                    e.preventDefault();
                    const val = e.target.value;
                    // Allow raw 7-digit codes or full URLs
                    if (val.length <= 7 && !isNaN(Number(val))) {
                      setCode(val);
                      return;
                    }
                    if (extractCode(val)) {
                      setCode(val);
                    }
                  }}
                  autoComplete="off"
                  type="text"
                ></Input>
              </>
            )}
            {modpack !== undefined && (
              <>
                <p>
                  {modpack.name} | {modpack.modLoader} | {modpack.version} |{" "}
                  {t("modCount", { amount: mods.length })}
                </p>
                <div className=" items-center justify-center my-4 rounded-4xl p-2 h-min  border-slate-900 border-8 ">
                  <div className="grid grid-cols-3 mb-0 2xl:grid-cols-4 gap-6 p-4 max-h-[35vh] max-w-[80vw] overflow-auto  ">
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
              </>
            )}
            <div className="flex w-full">
              <Button
                className={
                  "mt-2 w-full mr-1 " +
                  (progress === 1
                    ? "bg-emerald-600 hover:bg-emerald-700"
                    : "bg-slate-700 hover:bg-slate-700 cursor-not-allowed")
                }
                onClick={
                  modpack === undefined ? getModpack : installRemoteModpack
                }
              >
                {progress === 1
                  ? t("download")
                  : (progress * 100).toFixed(2) + "%"}
              </Button>
              {modpack === undefined && (
                <Button
                  className="mt-2 w-full ml-1 bg-blue-600 hover:bg-blue-700 "
                  onClick={async () => {
                    const clipboardText = await readClipboardText();
                    const extracted = extractCode(clipboardText);
                    if (extracted) {
                      setCode(clipboardText);
                    }
                  }}
                >
                  {t("paste")}
                </Button>
              )}
            </div>
          </div>
        </>
      )}
    </div>
  );
}
