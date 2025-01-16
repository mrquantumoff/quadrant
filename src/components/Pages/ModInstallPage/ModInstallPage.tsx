import { useContext, useEffect, useState } from "react";
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
import { ContentContext } from "../../../App";
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
import { LazyStore, load } from "@tauri-apps/plugin-store";
import { Field, Fieldset, Label, Select } from "@headlessui/react";
import Mod from "../../shared/Mod";
import LoaderOptions from "../../shared/LoaderOption";
import { listen } from "@tauri-apps/api/event";
import LinearProgress from "../../core/LinearProgress";

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
  const config = new LazyStore("config.json");
  useEffect(() => {
    const effect = async () => {
      setVersions(await getVersions());
      setModpacks(await getModpacks());
      setVersion((await config.get<string>("lastUsedVersion")) ?? "");
      setLoader((await config.get<string>("lastUsedAPI")) ?? "");
      setModpack((await config.get<string>("lastUsedModpack")) ?? "");
      const newOwners = await getModOwners(mod.source, mod.id);
      const newDeps = await getModDependencies(mod.source, mod.id);
      const roundIcons = await config.get<boolean>("clipIcons");
      setClipIcons(roundIcons ?? true);
      let newOwnersList: IModOwner[] = [];
      for (const owner of newOwners) {
        newOwnersList.push({
          name: owner,
          url: await getUserURL(owner, mod.source),
        });
      }
      setDeps(newDeps);
      setOwners(newOwnersList);
    };
    effect();
    listen<ModProgress>("modInstallProgress", (event) => {
      if (event.payload.modId === mod.id) {
        setModInstallProgress(event.payload.progress);
      }
    });
    listen<ModProgress>("modDownloadProgress", (event) => {
      if (event.payload.modId === mod.id) {
        setModDownloadProgress(event.payload.progress);
      }
    });
  }, []);

  useEffect(() => {
    const effect = async () => {
      const newDeps = await getModDependencies(mod.source, mod.id);
      setDeps(newDeps);
    };
    effect().catch(console.error);
  }, [mod]);

  const modSource =
    mod.source === ModSource.CurseForge
      ? "CurseForge"
      : mod.source === ModSource.Modrinth
      ? "Modrinth"
      : "?";

  return (
    <motion.div
      initial={{ y: 500, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      exit={{ y: 5000 }}
      className="overflow-hidden"
      key={mod.name}
    >
      <Button
        onClick={() => {
          context.back();
        }}
        className="bg-slate-800 mt-2 ml-4 rounded-2xl hover:bg-slate-700 flex text-center items-center "
      >
        <MdArrowBack className="w-10 h-10  " />
        {t("cancel")}
      </Button>
      <motion.div
        initial={{ x: 50, opacity: 0 }}
        animate={{ x: 0, opacity: 1 }}
        className="bg-slate-800 mb-5 overflow-y-auto rounded-2xl h-fit pb-8 mx-4 mt-2 flex flex-col items-start"
      >
        <div className="flex h-full w-full mt-8 ">
          <div className="flex flex-col items-start ml-12 h-min w-full mr-24">
            <div className="bg-slate-900 mt-6 rounded-2xl p-2 mb-4">
              <img
                src={mod.modIconUrl}
                className={"w-24 h-24 " + (clipIcons ? "rounded-full" : "")}
              ></img>
            </div>
            <h2 className="text-start text-4xl flex font-extrabold text-wrap">
              {mod.name}
            </h2>
            <h3 className="font-bold">
              {t(mod.modType.toLowerCase(), { source: modSource })}
            </h3>
            <div className="text-slate-400 rounded-2xl bg-slate-900 p-4 my-2 w-full">
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
                  <span className="w-fit h-full place-content-center text-2xl align-center justify-center text-center font-bold ">
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
          <div className="flex w-full self-end flex-col h-fit max-h-[60vh] items-center justify-center align-middle bg-slate-700 rounded-2xl overflow-x-hidden overflow-y-auto mr-8 mb-4">
            {mod.thumbnailUrls.map((thumbnail) => {
              return (
                <div key={thumbnail} className="h-full m-2 rounded-2xl">
                  <motion.img
                    src={thumbnail}
                    className="w-full h-full rounded-2xl"
                    whileHover={{ scale: 1.25 }}
                  ></motion.img>
                </div>
              );
            })}
          </div>
        </div>
      </motion.div>
      <motion.div
        initial={{ y: 50, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        className="bg-slate-800 overflow-x-auto rounded-2xl m-4 p-4 flex flex-col flex-1 items-center"
      >
        <h1 className="text-center text-4xl mb-2 font-extrabold">
          {t("owners", { amount: owners.length })}:
        </h1>
        <div className="flex flex-row w-full overflow-auto">
          {owners.map((owner) => {
            return (
              <div
                key={owner.name}
                className="p-2 mx-2 items-center text-center h-5/6 w-fit bg-slate-700 rounded-2xl"
              >
                <p className="font-extrabold text-3xl">{owner.name}</p>
                <Button
                  onClick={async () => {
                    openIn(owner.url);
                  }}
                  className="bg-sky-600 hover:bg-sky-800 h-fit"
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
        initial={{ y: 50, opacity: 0 }}
        animate={{ opacity: 0.25 }}
        whileInView={{ y: 0, opacity: 1 }}
        className="bg-slate-800 overflow-y-auto rounded-2xl m-4 p-4 flex flex-row flex-1"
      >
        <Fieldset className="w-full">
          {props.fileId === undefined ? (
            <Field>
              <Label className="block my-2 font-bold">
                {t("chooseVersion")}
              </Label>
              <Select
                className="bg-slate-700 w-full p-2 rounded-2xl font-semibold hover:bg-slate-600"
                name="version"
                autoComplete="off"
                onChange={async (e) => {
                  e.preventDefault();
                  setVersion(e.target.value);
                  const config = await load("config.json");
                  await config.set("lastUsedVersion", e.target.value);
                }}
                value={version}
              >
                {versions.map((versionOption) => {
                  return (
                    <option
                      value={versionOption.version}
                      defaultChecked={versionOption.version === version}
                      className="rounded-2xl font-semibold"
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
                className="bg-slate-700 w-full p-2 rounded-2xl font-semibold hover:bg-slate-600"
                name="modLoader"
                onChange={async (e) => {
                  e.preventDefault();
                  setLoader(e.target.value);
                  const config = await load("config.json");
                  await config.set("lastUsedAPI", e.target.value);
                }}
                value={loader}
                autoComplete="off"
              >
                <LoaderOptions loader={loader} />
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
                className="bg-slate-700 focus:bg-slate-600 focus: focus:border-2 focus:border-slate-500 w-full p-2 rounded-2xl font-semibold hover:bg-slate-600"
                name="modpack"
                autoComplete="off"
                value={modpack}
                onChange={async (e) => {
                  e.preventDefault();
                  const modpack = modpacks.filter(
                    (i) => i.name === e.target.value
                  )[0];
                  setModpack(e.target.value);
                  setLoader(modpack.modLoader.toString());
                  setVersion(modpack.version);
                  const config = await load("config.json");

                  await config.set("lastUsedVersion", modpack.version);
                  await config.set("lastUsedAPI", modpack.modLoader.toString());
                  await config.set("lastUsedModpack", modpack.name);
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
              className={
                "self-center flex w-full flex-1 h-full items-center bg-emerald-600 hover:bg-emerald-800 mt-8"
              }
              onClick={async () => {
                try {
                  await installMod(
                    mod.id,
                    version,
                    loader as ModLoader,
                    mod.source,
                    mod.modType,
                    modpack,
                    props.fileId
                  );
                } catch (e: any) {
                  console.error(t(e));
                  context.setSnackbar({
                    message: t(e),
                    className: "bg-red-500 rounded-2xl",
                    timeout: 5000,
                  });
                }
              }}
            >
              <MdDownload className="w-6 h-6 mr-2 self-center" />
              {t("download")}
            </Button>
            <Button
              className={
                "self-center flex flex-1 h-full items-center bg-sky-600 hover:bg-sky-800 mt-2 w-full"
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
