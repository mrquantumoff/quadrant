/** @format */
import { useTranslation } from "react-i18next";
import {
  ContentContext,
  IMod,
  ModLoader,
  ModpackViewContext,
  ModSource,
  ModType,
} from "../../intefaces";
import {
  MdCheck,
  MdDelete,
  MdDownload,
  MdFileDownload,
  MdOpenInNew,
} from "react-icons/md";
import { motion } from "motion/react";
import {
  deleteMod,
  installMod,
  installRemoteFile,
  openIn,
  registerMod,
} from "../../tools";
import { useContext, useEffect, useRef, useState } from "react";
import ModInstallPage from "../Pages/ModInstallPage/ModInstallPage";
import Button from "../core/Button";
import "./Mod.css";
import { createDesktopStore, listen } from "../../desktop";

export interface IModProps {
  mod: IMod;
  modpack: string | undefined;
  className: string;
}

/** Deterministic hue (0-359) from a string, for the gradient fallback tile. */
function hashHue(value: string): number {
  let hue = 0;
  for (let i = 0; i < value.length; i++) {
    hue = (hue * 31 + value.charCodeAt(i)) % 360;
  }
  return hue;
}

export default function Mod(props: IModProps) {
  const mod = props.mod;
  const { t, i18n } = useTranslation();
  const isCurseForge = mod.source === ModSource.CurseForge;
  const isModrinth = mod.source === ModSource.Modrinth;
  const sourceLabel = isCurseForge
    ? "CurseForge"
    : isModrinth
      ? "Modrinth"
      : "";
  // Modpacks and data packs are browsable but not one-click installable; the
  // card surfaces "open in web" for them instead of a download action.
  const installable =
    mod.modType !== ModType.Modpack && mod.modType !== ModType.DataPack;
  const description = mod.description.trim();

  const [visible, setVisible] = useState(true);
  const [clickableDownload, setClickableDownload] = useState(true);
  const [clipIcons, setClipIcons] = useState(true);

  const [progress, setProgress] = useState(-1);

  const context = useContext(ContentContext);
  const installRequestedRef = useRef(false);
  const installInFlightRef = useRef(false);

  const configRef = useRef(createDesktopStore("config.json"));
  const config = configRef.current;
  const cardRef = useRef<HTMLDivElement>(null);
  const modpackViewContext = useContext(ModpackViewContext);
  const modId = mod.id;
  const isAutoinstallable = mod.autoinstallable;

  const openModDownload = async () => {
    if (!mod.downloadable || !installable) {
      return;
    }
    // 8 character random string
    const randomString = Math.random().toString(36).substring(2, 10);
    const originRect = cardRef.current?.getBoundingClientRect();

    context.changeContent({
      title: mod.name,
      icon: <img src={mod.modIconUrl ?? null}></img>,
      // Keyed so opening a dependency from an install page remounts the page.
      content: (
        <ModInstallPage key={mod.id} mod={mod} originRect={originRect} />
      ),
      name: randomString, // This is for the back content function to work properly
      style: "",
      main: false,
      ownTransition: originRect !== undefined,
    });
  };

  useEffect(() => {
    let isUnmounted = false;
    let unlistenProgress: (() => void | Promise<void>) | null = null;
    let unlistenInstallProgress: (() => void | Promise<void>) | null = null;

    const effect = async () => {
      try {
        unlistenProgress = await listen("modDownloadProgress", (event: any) => {
          if (event.payload.modId === modId) {
            setProgress(event.payload.progress);
            if (event.payload.progress === 100) {
              unlistenProgress?.();
              unlistenProgress = null;
            }
          }
        });
        if (isUnmounted && unlistenProgress) {
          unlistenProgress();
          unlistenProgress = null;
        }

        const roundIcons = await config.get<boolean>("clipIcons");
        if (!isUnmounted) {
          setClipIcons(roundIcons ?? true);
        }

        unlistenInstallProgress = await listen(
          "modInstallProgress",
          (event: any) => {
            if (
              event.payload.modId === modId &&
              event.payload.progress === 100
            ) {
              console.log(event);

              if (!isAutoinstallable) {
                setVisible(false);
              }
              setProgress(event.payload.progress);
              unlistenInstallProgress?.();
              unlistenInstallProgress = null;
            }
          },
        );
        if (isUnmounted && unlistenInstallProgress) {
          unlistenInstallProgress();
          unlistenInstallProgress = null;
        }
      } catch (error) {
        console.error(error);
      }
    };

    effect().catch(console.error);

    return () => {
      isUnmounted = true;
      if (unlistenProgress) {
        unlistenProgress();
      }
      if (unlistenInstallProgress) {
        unlistenInstallProgress();
      }
    };
  }, [config, isAutoinstallable, modId]);

  useEffect(() => {
    if (isAutoinstallable && progress === 100 && installRequestedRef.current) {
      installRequestedRef.current = false;
      installInFlightRef.current = false;
      context.setSnackbar({
        message: t("downloadSuccess"),
        className: "bg-emerald-600",
        timeout: 3000,
      });
    }
  }, [context, isAutoinstallable, progress, t]);

  const downloadCount = Intl.NumberFormat(i18n.language, {
    compactDisplay: "short",
    notation: "compact",
    maximumFractionDigits: 1,
  }).format(mod.downloadCount);

  const hue = hashHue(mod.name);
  const gradientTile = `linear-gradient(135deg, hsl(${hue} 58% 50%), hsl(${(hue + 45) % 360} 55% 38%))`;

  const actionButtonClass =
    "flex items-center gap-1.5 h-8 px-5 rounded-full font-extrabold text-xs text-white whitespace-nowrap self-center";
  const iconButtonClass =
    "inline-flex items-center justify-center w-[38px] h-[38px] rounded-full bg-slate-800 text-slate-300 hover:bg-slate-700 hover:text-slate-50 self-center";

  return (
    <>
      {visible && (
        <motion.div
          ref={cardRef}
          initial={{ opacity: 0, y: 24 }}
          animate={{ y: 0, opacity: 1, x: 0 }}
          exit={{ opacity: 0, y: -24 }}
          transition={{ type: "spring", stiffness: 100, duration: 0.3 }}
          className={
            props.className +
            " flex flex-col gap-2.5 h-full w-full p-4 bg-slate-900 rounded-2xl hover:bg-slate-950 hover:shadow-2xl hover:shadow-slate-950 transition-[background,box-shadow] transform-gpu backface-hidden will-change-[transform,opacity]"
          }
          onDoubleClick={openModDownload}
        >
          {/* Header: icon tile + name/meta/description */}
          <div className="flex items-start gap-3">
            {mod.modIconUrl && mod.modIconUrl.trim().length !== 0 ? (
              <img
                src={mod.modIconUrl}
                height="56px"
                width="56px"
                className={
                  "flex-none w-14 h-14 object-cover bg-slate-800" +
                  (clipIcons ? " rounded-full" : " rounded-2xl")
                }
              ></img>
            ) : (
              <div
                className={
                  "flex-none w-14 h-14 flex items-center justify-center text-2xl font-extrabold text-white" +
                  (clipIcons ? " rounded-full" : " rounded-2xl")
                }
                style={{ background: gradientTile }}
              >
                {mod.name.trim().charAt(0).toUpperCase() || "?"}
              </div>
            )}
            <div className="flex-1 min-w-0 flex flex-col gap-px">
              <span className="text-base font-black tracking-tight truncate">
                {mod.name}
              </span>
              <div className="flex items-center gap-1.5 text-xs text-slate-400 font-bold">
                <MdDownload className="w-3.25 h-3.25" />
                {downloadCount}
                {sourceLabel && (
                  <>
                    <span className="text-slate-600">·</span>
                    <span
                      className={
                        "px-2 py-0.5 rounded-full text-[11px] font-extrabold " +
                        (isCurseForge
                          ? "bg-orange-500/20 text-orange-400"
                          : "bg-emerald-500/15 text-emerald-400")
                      }
                    >
                      {sourceLabel}
                    </span>
                  </>
                )}
              </div>
              <p className="text-xs leading-4.5 text-slate-400 line-clamp-2 overflow-hidden m-0 h-9">
                {description}
              </p>
            </div>
          </div>

          {/* Actions */}
          <div className="flex items-center justify-end gap-2 mt-auto">
            {mod.deleteable && (
              <Button
                animate
                onClick={async () => {
                  await deleteMod(props.modpack ?? "free", mod.id);
                  setVisible(false);
                }}
                className={actionButtonClass + " bg-slate-800 hover:bg-red-700"}
              >
                {t("delete")}
                <MdDelete className="w-5 h-5" />
              </Button>
            )}
            {mod.downloadable && installable && progress !== 100 ? (
              mod.newVersion !== undefined && mod.showPreviousVersion ? (
                <Button
                  animate
                  onClick={async () => {
                    if (!clickableDownload || installInFlightRef.current) {
                      return;
                    }
                    installInFlightRef.current = true;
                    setClickableDownload(false);
                    installRequestedRef.current = true;
                    try {
                      await installRemoteFile(
                        mod.newVersion!,
                        mod.modType,
                        props.modpack,
                        mod.source,
                        mod.id,
                      );
                    } catch (e: any) {
                      installRequestedRef.current = false;
                      installInFlightRef.current = false;
                      setClickableDownload(true);
                      context.setSnackbar({
                        message: t(e),
                        className: "bg-red-700",
                        timeout: 3000,
                      });
                    }
                  }}
                  className={
                    actionButtonClass + " bg-emerald-600 hover:bg-emerald-700"
                  }
                >
                  {progress === -1 ? t("update") : +progress.toFixed(2) + "%"}
                  <MdFileDownload className="w-5 h-5"></MdFileDownload>
                </Button>
              ) : (
                <Button
                  animate
                  onClick={async () => {
                    if (progress !== -1 || installInFlightRef.current) {
                      return;
                    }
                    console.log("Autoinstallable: " + mod.autoinstallable);
                    if (mod.autoinstallable) {
                      installInFlightRef.current = true;
                      setClickableDownload(false);
                      installRequestedRef.current = true;
                      // Get last used api, modpack, and loader
                      const config = createDesktopStore("config.json");
                      const lastUsedAPI =
                        await config.get<string>("lastUsedAPI");
                      const lastUsedModpack =
                        await config.get<string>("lastUsedModpack");
                      const lastUsedVersion =
                        await config.get<string>("lastUsedVersion");
                      try {
                        await installMod(
                          mod.id,
                          lastUsedVersion ?? "",
                          (lastUsedAPI as ModLoader) ?? ModLoader.Unknown,
                          mod.source,
                          mod.modType,
                          lastUsedModpack ?? "free",
                        );
                      } catch (e: any) {
                        installRequestedRef.current = false;
                        installInFlightRef.current = false;
                        setClickableDownload(true);
                        context.setSnackbar({
                          message: t(e),
                          className: "bg-red-700",
                          timeout: 3000,
                        });
                      }
                      return;
                    }
                    openModDownload();
                  }}
                  className={
                    actionButtonClass + " bg-emerald-600 hover:bg-emerald-700"
                  }
                >
                  {progress === -1 ? t("download") : +progress.toFixed(2) + "%"}
                  <MdFileDownload className="w-5 h-5"></MdFileDownload>
                </Button>
              )
            ) : (
              <></>
            )}
            {mod.selectable && (
              <Button
                animate
                className={actionButtonClass + " bg-blue-600 hover:bg-blue-700"}
                onClick={async () => {
                  await registerMod(
                    {
                      downloadUrl: mod.selectUrl ?? "",
                      id: mod.id,
                      source: mod.source,
                    },
                    mod.modpack ?? "",
                  );
                  modpackViewContext.removeMod(mod.id);
                }}
              >
                {t("select")}
                <MdCheck className="size-2"></MdCheck>
              </Button>
            )}
            {mod.url.trim().length !== 0 && (
              <button
                title={t("openInTheWeb")}
                onClick={async () => {
                  await openIn(mod.url);
                }}
                className={iconButtonClass}
              >
                <MdOpenInNew className="size-4" />
              </button>
            )}
          </div>
        </motion.div>
      )}
    </>
  );
}
