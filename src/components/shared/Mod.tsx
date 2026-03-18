/** @format */
import { useTranslation } from "react-i18next";
import {
  ContentContext,
  IMod,
  ModLoader,
  ModpackViewContext,
  ModSource,
} from "../../intefaces";
import {
  MdCheck,
  MdDelete,
  MdDownload,
  MdFileDownload,
  MdOpenInBrowser,
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
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { LazyStore } from "@tauri-apps/plugin-store";
import Button from "../core/Button";
import "./Mod.css";

export interface IModProps {
  mod: IMod;
  modpack: string | undefined;
  className: string;
}

export default function Mod(props: IModProps) {
  const mod = props.mod;
  const { t, i18n } = useTranslation();
  const modSource =
    mod.source === ModSource.CurseForge
      ? "CurseForge"
      : mod.source === ModSource.Modrinth
        ? "Modrinth"
        : "?";
  const desc = (
    mod.description.trim().length >= 36
      ? mod.description.trim().substring(0, 36) + "..."
      : mod.description
  ).trim();

  const [visible, setVisible] = useState(true);
  const [clickableDownload, setClickableDownload] = useState(true);
  const [clipIcons, setClipIcons] = useState(true);

  const [progress, setProgress] = useState(-1);

  const context = useContext(ContentContext);
  const installRequestedRef = useRef(false);

  const configRef = useRef<LazyStore | null>(null);
  if (configRef.current === null) {
    configRef.current = new LazyStore("config.json");
  }
  const config = configRef.current!;
  const modpackViewContext = useContext(ModpackViewContext);
  const modId = mod.id;
  const isAutoinstallable = mod.autoinstallable;

  const openModDownload = async () => {
    if (!mod.downloadable) {
      return;
    }
    // 8 character random string
    const randomString = Math.random().toString(36).substring(2, 10);

    context.changeContent({
      title: mod.name,
      icon: <img src={mod.modIconUrl ?? null}></img>,
      content: <ModInstallPage mod={mod} />,
      name: randomString, // This is for the back content function to work properly
      style: "",
      main: false,
    });
  };

  useEffect(() => {
    let isUnmounted = false;
    let unlistenProgress: UnlistenFn | null = null;
    let unlistenInstallProgress: UnlistenFn | null = null;

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
  }, [isAutoinstallable, modId]);

  useEffect(() => {
    if (isAutoinstallable && progress === 100 && installRequestedRef.current) {
      installRequestedRef.current = false;
      context.setSnackbar({
        message: t("downloadSuccess"),
        className: "bg-emerald-700 text-white",
        timeout: 3000,
      });
    }
  }, [context, isAutoinstallable, progress, t]);

  return (
    <>
      {visible && (
        <motion.div
          initial={{
            opacity: 0,
            y: 50,
          }}
          whileInView={{ opacity: 1, y: 0, x: 0 }}
          animate={{ y: 0, opacity: 1 }}
          whileHover={{ opacity: 1, y: -5, x: 0 }}
          exit={{
            opacity: 0,
            y: -500,
          }}
          transition={{ type: "spring", stiffness: 100, duration: 300 }}
          className={
            props.className +
            " p-4 h-full bg-slate-900 w-full flex-1 items-center justify-center align-middle rounded-4xl flex flex-col hover:shadow-2xl hover:bg-slate-950 hover:shadow-slate-950"
          }
          onDoubleClick={openModDownload}
        >
          <div className="flex flex-row">
            <span className="w-full"></span>
            <img
              src={mod.modIconUrl}
              height={"64px"}
              width={"64px"}
              className={
                "align-center justify-center" +
                (clipIcons ? " rounded-full" : "")
              }
            ></img>
            <span className="w-full"></span>
          </div>
          <div className="flex line-clamp-1 mt-4 w-full place-content-center align-center text-center justify-center">
            <h1 className="max-w-full line-clamp-1 h-full text-2xl align-center justify-center text-center font-bold mod-title-transition ">
              {mod.name}
            </h1>

            <span className="flex text-slate-400 rounded-4xl">
              <span className="border-2 mx-2 border-slate-400"></span>
              <span className="w-fit h-full place-content-center text-2xl align-center justify-center text-center font-bold ">
                {Intl.NumberFormat(i18n.language, {
                  compactDisplay: "short",
                  notation: "compact",
                  maximumFractionDigits: 1,
                }).format(mod.downloadCount)}
              </span>
              <span className="place-content-center align-center justify-center">
                <MdDownload className="w-6 h-6 place-content-center align-center justify-center text-center font-bold" />
              </span>
            </span>
          </div>
          <p className="w-full line-clamp-1 text-base align-center text-center text-slate-400">
            {desc}
          </p>
          <h2 className="w-full line-clamp-1 text-sm align-center justify-center text-center text-slate-400">
            {t(mod.modType.toLowerCase(), { source: modSource })}
          </h2>
          <div className="flex h-min align-center w-full items-center justify-center text-center mt-4 transition-all duration-300 ease-linear">
            {mod.deleteable ? (
              <Button
                animate
                onClick={async () => {
                  await deleteMod(props.modpack ?? "free", mod.id);
                  setVisible(false);
                }}
                className="flex justify-center items-center w-full h-full text-lg/none text-pretty self-center bg-red-700 hover:bg-red-800 font-extrabold px-2 py-1 rounded-4xl mx-2"
              >
                {t("delete")}
                <MdDelete className="ml-2 w-6 h-6" />
              </Button>
            ) : (
              <></>
            )}
            {mod.downloadable && progress !== 100 ? (
              mod.newVersion !== undefined && mod.showPreviousVersion ? (
                <Button
                  animate
                  onClick={async () => {
                    if (!clickableDownload) {
                      return;
                    }
                    setClickableDownload(false);
                    installRequestedRef.current = true;
                    await deleteMod(props.modpack!, mod.id);

                    await installRemoteFile(
                      mod.newVersion!,
                      mod.modType,
                      props.modpack,
                      mod.source,
                      mod.id,
                    );
                  }}
                  className="flex justify-center items-center w-full h-full text-lg/none text-pretty self-center bg-emerald-700 hover:bg-emerald-800 font-extrabold px-2 py-1 rounded-4xl mx-2"
                >
                  {progress === -1 ? t("update") : +progress.toFixed(2) + "%"}
                  <MdFileDownload className="ml-2 w-6 h-6"></MdFileDownload>
                </Button>
              ) : (
                <Button
                  animate
                  onClick={async () => {
                    if (progress !== -1) {
                      return;
                    }
                    console.log("Autoinstallable: " + mod.autoinstallable);
                    if (mod.autoinstallable) {
                      installRequestedRef.current = true;
                      // Get last used api, modpack, and loader
                      const config = new LazyStore("config.json");
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
                        context.setSnackbar({
                          message: t(e),
                          className: "bg-red-700 text-white",
                          timeout: 3000,
                        });
                      }
                      return;
                    }
                    openModDownload();
                  }}
                  className="flex justify-center items-center w-full h-full text-lg/none text-pretty self-center bg-emerald-700 hover:bg-emerald-800 font-extrabold px-2 py-1 rounded-4xl mx-2"
                >
                  {progress === -1 ? t("download") : +progress.toFixed(2) + "%"}
                  <MdFileDownload className="ml-2 w-6 h-6"></MdFileDownload>
                </Button>
              )
            ) : (
              <></>
            )}
            {mod.selectable && (
              <Button
                animate
                className="flex items-center w-full text-lg/none self-center h-full wrap-break-word text-center justify-center bg-blue-700 hover:bg-blue-800 font-extrabold px-2 py-1 rounded-4xl mx-2"
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
                <MdCheck className="ml-2 w-6 h-6"></MdCheck>
              </Button>
            )}
            {mod.url.trim().length !== 0 && (
              <Button
                onClick={async () => {
                  await openIn(mod.url);
                }}
                animate
                className="flex items-center w-full text-lg/none self-center h-full wrap-break-word text-center justify-center bg-blue-700 hover:bg-blue-800 font-extrabold px-2 py-1 rounded-4xl mx-2"
              >
                {t("openInTheWeb")}
                <MdOpenInBrowser className="ml-2 w-6 h-6"></MdOpenInBrowser>
              </Button>
            )}
          </div>
        </motion.div>
      )}
    </>
  );
}
