/** @format */

import { useContext, useEffect, useRef, useState } from "react";
import "./ModInstallPage.css";
import {
  IMod,
  LocalModpack,
  MinecraftVersion,
  ModLoader,
  ModProgress,
  ModSource,
  ModType,
} from "../../../intefaces";
import Button from "../../core/Button";
import { ContentContext } from "../../../intefaces";
import { MdArrowBack, MdDownload, MdOpenInBrowser } from "react-icons/md";
import { motion } from "motion/react";
import { useTranslation } from "react-i18next";
import {
  getModDependencies,
  getModOwners,
  getModpacks,
  getUserURL,
  getVersions,
  installMod,
  openIn,
} from "../../../tools";
import { Field, Fieldset, Label, Select } from "@headlessui/react";
import Mod from "../../shared/Mod";
import LoaderOptions from "../../shared/LoaderOption";
import LinearProgress from "../../core/LinearProgress";
import { createDesktopStore, listen } from "../../../desktop";
import { loaderProvidersForSource } from "../../../modLoaders";

export interface IModInstallPageProps {
  mod: IMod;
  fileId?: string;
}

interface IModOwner {
  name: string;
  url: string;
}

export default function ModInstallPage(props: IModInstallPageProps) {
  const mod = props.mod;

  const context = useContext(ContentContext);
  const { t, i18n } = useTranslation();
  const [versions, setVersions] = useState<MinecraftVersion[]>([]);
  const [modpacks, setModpacks] = useState<LocalModpack[]>([]);
  const [version, setVersion] = useState<string>("");
  const [modpack, setModpack] = useState<string>("");
  const [loader, setLoader] = useState<string>("");
  const [owners, setOwners] = useState<IModOwner[]>([]);
  const [deps, setDeps] = useState<IMod[]>([]);
  const [clipIcons, setClipIcons] = useState(true);
  const [modInstallProgress, setModInstallProgress] = useState<number>(0);
  const [modDownloadProgress, setModDownloadProgress] = useState<number>(0);
  const [isInstalling, setIsInstalling] = useState(false);
  const [isReady, setIsReady] = useState(false);
  const installInFlightRef = useRef(false);
  const configRef = useRef(createDesktopStore("config.json"));
  const config = configRef.current;
  useEffect(() => {
    let cancelled = false;
    setIsReady(false);
    const effect = async () => {
      const [
        availableVersions,
        availableModpacks,
        savedVersion,
        savedLoader,
        savedModpack,
      ] = await Promise.all([
        getVersions(),
        getModpacks(),
        config.get<string>("lastUsedVersion"),
        config.get<string>("lastUsedAPI"),
        config.get<string>("lastUsedModpack"),
      ]);
      if (cancelled) return;
      const target =
        mod.modType === ModType.Mod
          ? (availableModpacks.find((entry) => entry.name === savedModpack) ??
            availableModpacks.find((entry) => entry.isApplied) ??
            availableModpacks[0])
          : undefined;
      const initialVersion =
        target?.version ??
        availableVersions.find((entry) => entry.version === savedVersion)
          ?.version ??
        availableVersions[0]?.version ??
        "";
      setVersions(availableVersions);
      setModpacks(availableModpacks);
      setVersion(initialVersion);
      setLoader(target?.modLoader ?? savedLoader ?? ModLoader.Unknown);
      setModpack(target?.name ?? "");
      setIsReady(true);
    };
    effect().catch(console.error);
    return () => {
      cancelled = true;
    };
  }, [config, mod.modType]);

  useEffect(() => {
    let cancelled = false;
    const unlisteners: Array<() => void | Promise<void>> = [];
    setDeps([]);
    setOwners([]);
    const effect = async () => {
      const [newOwners, newDeps, roundIcons] = await Promise.all([
        getModOwners(mod.source, mod.id),
        getModDependencies(mod.source, mod.id),
        config.get<boolean>("clipIcons"),
      ]);
      const newOwnersList = await Promise.all(
        newOwners.map(async (owner) => ({
          name: owner,
          url: await getUserURL(owner, mod.source),
        })),
      );
      if (cancelled) return;
      setClipIcons(roundIcons ?? true);
      setDeps(newDeps);
      setOwners(newOwnersList);
    };
    effect().catch(console.error);
    for (const [eventName, setProgress] of [
      ["modInstallProgress", setModInstallProgress],
      ["modDownloadProgress", setModDownloadProgress],
    ] as const) {
      void listen<ModProgress>(eventName, (event) => {
        if (!cancelled && event.payload.modId === mod.id) {
          setProgress(event.payload.progress);
        }
      })
        .then((unlisten) => {
          if (cancelled) return unlisten();
          unlisteners.push(unlisten);
        })
        .catch(console.error);
    }
    return () => {
      cancelled = true;
      unlisteners.forEach((unlisten) => void unlisten());
    };
  }, [config, mod.id, mod.source]);

  const modSource =
    mod.source === ModSource.CurseForge
      ? "CurseForge"
      : mod.source === ModSource.Modrinth
        ? "Modrinth"
        : "?";
  // Install flow targets one provider, so hide loaders that provider cannot resolve.
  const loaderProviders = loaderProvidersForSource(mod.source);

  return (
    <motion.div
      initial={{ y: 24, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      exit={{ y: -24, opacity: 0 }}
      className="overflow-hidden transform-gpu [backface-visibility:hidden] [will-change:transform,opacity]"
      key={mod.name}
    >
      <Button
        onClick={() => {
          context.back();
        }}
        className="bg-slate-800 mt-2 ml-4 rounded-4xl hover:bg-slate-700 flex text-center items-center "
      >
        <MdArrowBack className="w-6 h-6 mr-1 " />
        {t("cancel")}
      </Button>
      <motion.div
        initial={{ x: 50, opacity: 0 }}
        animate={{ x: 0, opacity: 1 }}
        className="bg-slate-800 mb-5 overflow-y-auto rounded-4xl h-fit pb-8 mx-4 mt-2 flex flex-col items-start"
      >
        <div className="flex flex-col lg:flex-row h-full w-full mt-4 ">
          <div className="flex flex-col items-start ml-6 h-min w-full mr-6">
            <div className="bg-slate-900 mt-6 rounded-4xl p-2 mb-4">
              <img
                src={mod.modIconUrl}
                className={"w-24 h-24 " + (clipIcons ? "rounded-full" : "")}
              ></img>
            </div>
            <h2 className="text-start text-2xl flex font-extrabold text-wrap">
              {mod.name}
            </h2>
            <h3 className="font-bold">
              {t(mod.modType.toLowerCase(), { source: modSource })}
            </h3>
            <div className="text-slate-400 rounded-4xl bg-slate-900 p-4 my-2 w-full">
              <div className="flex flex-col">
                <p className="text-start text-lg text-pretty w-full font-semibold my-2">
                  {mod.description}
                </p>
                {mod.source == ModSource.Modrinth && (
                  <p className="text-start text-base text-wrap">
                    {t("licensedUnder", { license: mod.license })}
                  </p>
                )}
              </div>
              <div className="flex flex-col ">
                <span className="border-2 my-4 h-full w-full rounded-full border-slate-400"></span>
                <div className="flex flex-row items-center justify-center">
                  <span className="w-fit h-full place-content-center text-lg align-center justify-center text-center font-bold ">
                    {Intl.NumberFormat(i18n.language, {
                      compactDisplay: "short",
                      notation: "compact",
                      maximumFractionDigits: 1,
                    }).format(mod.downloadCount)}
                  </span>
                  <span className="place-content-center align-center justify-center ml-2">
                    <MdDownload className="w-6 h-6 place-content-center align-center justify-center text-center font-bold" />
                  </span>
                </div>
              </div>
            </div>
          </div>
          <div className="flex w-full self-end flex-col h-fit max-h-[60vh] items-center  align-middle bg-slate-700 rounded-4xl overflow-x-hidden oveflow-y-auto mr-8 mb-4">
            {mod.thumbnailUrls.map((thumbnail) => {
              return (
                <div
                  key={thumbnail}
                  className="h-full m-2 rounded-4xl overflow-y-visible"
                >
                  <motion.img
                    src={thumbnail}
                    className="w-full h-full rounded-4xl"
                    whileHover={{ scale: 1.5 }}
                    onClick={() => {
                      openIn(thumbnail);
                    }}
                  ></motion.img>
                </div>
              );
            })}
          </div>
        </div>
      </motion.div>
      <motion.div
        initial={{ y: 24, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        className="bg-slate-800 overflow-x-auto rounded-4xl m-4 p-4 flex flex-col flex-1 items-center transform-gpu [backface-visibility:hidden] [will-change:transform,opacity]"
      >
        <h1 className="text-center text-2xl mb-2 font-extrabold">
          {t("owners", { amount: owners.length })}:
        </h1>
        <div className="flex flex-row w-full overflow-auto">
          {owners.map((owner) => {
            return (
              <div
                key={owner.name}
                className="p-2 mx-2 items-center text-center h-5/6 w-fit bg-slate-700 rounded-4xl"
              >
                <p className="font-extrabold text-xl">{owner.name}</p>
                <Button
                  onClick={async () => {
                    openIn(owner.url);
                  }}
                  className="bg-blue-600 hover:bg-blue-700 h-fit"
                >
                  <p className="flex items-center">
                    <MdOpenInBrowser className="w-6 h-6 mr-2" />
                    {t("openInTheWeb")}
                  </p>
                </Button>
              </div>
            );
          })}
        </div>
      </motion.div>
      <motion.div
        initial={{ y: 24, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        className="bg-slate-800 overflow-y-auto rounded-4xl m-4 p-4 flex flex-row flex-1 transform-gpu [backface-visibility:hidden] [will-change:transform,opacity]"
      >
        <Fieldset className="w-full">
          {props.fileId === undefined ? (
            <Field>
              <Label className="block my-2 font-bold">
                {t("chooseVersion")}
              </Label>
              <Select
                className="bg-slate-700 w-full p-2 rounded-4xl font-semibold hover:bg-slate-600"
                name="version"
                autoComplete="off"
                onChange={async (e) => {
                  e.preventDefault();
                  setVersion(e.target.value);
                  await config.set("lastUsedVersion", e.target.value);
                  await config.save();
                }}
                value={version}
              >
                {version &&
                  !versions.some((entry) => entry.version === version) && (
                    <option value={version}>{version}</option>
                  )}
                {versions.map((versionOption) => {
                  return (
                    <option
                      value={versionOption.version}
                      defaultChecked={versionOption.version === version}
                      className="rounded-4xl font-semibold"
                      key={versionOption.version}
                    >
                      {versionOption.version}
                    </option>
                  );
                })}
              </Select>
            </Field>
          ) : (
            <></>
          )}

          {mod.modType === ModType.Mod && props.fileId === undefined ? (
            <Field>
              <Label className="block my-2 font-bold">
                {t("choosePreferredAPI")}
              </Label>
              <Select
                className="bg-slate-700 w-full p-2 rounded-4xl font-semibold hover:bg-slate-600"
                name="modLoader"
                onChange={async (e) => {
                  e.preventDefault();
                  setLoader(e.target.value);
                  await config.set("lastUsedAPI", e.target.value);
                  await config.save();
                }}
                value={loader}
                autoComplete="off"
              >
                <LoaderOptions loader={loader} providers={loaderProviders} />
              </Select>
            </Field>
          ) : (
            <></>
          )}
          {mod.modType === ModType.Mod && (
            <Field>
              <Label className="block my-2 font-bold">
                {t("chooseModpack")}
              </Label>
              <Select
                className="bg-slate-700 focus:bg-slate-600 focus: focus:border-2 focus:border-slate-500 w-full p-2 rounded-4xl font-semibold hover:bg-slate-600"
                name="modpack"
                autoComplete="off"
                value={modpack}
                onChange={async (e) => {
                  e.preventDefault();
                  const modpack = modpacks.filter(
                    (i) => i.name === e.target.value,
                  )[0];
                  setModpack(e.target.value);
                  setLoader(modpack.modLoader.toString());
                  setVersion(modpack.version);
                  await config.set("lastUsedVersion", modpack.version);
                  await config.set("lastUsedAPI", modpack.modLoader.toString());
                  await config.set("lastUsedModpack", modpack.name);
                  await config.save();
                }}
              >
                {modpacks.map((modpack) => (
                  <option key={modpack.name} value={modpack.name}>
                    {modpack.name} | {modpack.modLoader} | {modpack.version}
                  </option>
                ))}
              </Select>
            </Field>
          )}
          <div className="flex flex-col items-center justify-center">
            <LinearProgress
              className="my-2 mt-8"
              progress={modInstallProgress}
            />
            <LinearProgress className="my-2" progress={modDownloadProgress} />
            <Button
              disabled={
                !isReady ||
                isInstalling ||
                (props.fileId === undefined && !version) ||
                (mod.modType === ModType.Mod && !modpack)
              }
              className={
                "self-center flex w-full flex-1 h-full items-center mt-8 " +
                (isInstalling
                  ? "bg-slate-700 cursor-not-allowed"
                  : "bg-emerald-600 hover:bg-emerald-700")
              }
              onClick={async () => {
                if (
                  !isReady ||
                  installInFlightRef.current ||
                  (props.fileId === undefined && !version) ||
                  (mod.modType === ModType.Mod && !modpack)
                ) {
                  return;
                }
                installInFlightRef.current = true;
                setIsInstalling(true);
                try {
                  await installMod(
                    mod.id,
                    version,
                    loader as ModLoader,
                    mod.source,
                    mod.modType,
                    modpack,
                    props.fileId,
                  );
                } catch (e: any) {
                  console.error(t(e));
                  context.setSnackbar({
                    message: t(e),
                    className: "bg-red-700 rounded-4xl",
                    timeout: 5000,
                  });
                } finally {
                  installInFlightRef.current = false;
                  setIsInstalling(false);
                }
              }}
            >
              <MdDownload className="w-6 h-6 mr-2 self-center" />
              {t("download")}
            </Button>
            <Button
              className={
                "self-center flex flex-1 h-full items-center bg-blue-600 hover:bg-blue-700 mt-2 w-full"
              }
              onClick={async () => {
                await openIn(mod.url);
              }}
            >
              <MdOpenInBrowser className="w-6 h-6 mr-2 self-center" />
              {t("openInTheWeb")}
            </Button>
          </div>
        </Fieldset>
        <div className="w-full ml-16 mx-4 flex flex-col items-center overflow-y-auto max-h-[60vh]">
          {deps.length === 0 && (
            <p className="m-8 font-extrabold">{t("emptyDependencies")}</p>
          )}

          {deps.map((dependency) => {
            return (
              <Mod
                key={dependency.id}
                mod={dependency}
                modpack={undefined}
                className={"w-full my-2 mx-0 self-center"}
              ></Mod>
            );
          })}
        </div>
      </motion.div>
    </motion.div>
  );
}
