import { useContext, useEffect, useState } from "react";
import { LocalModpack, MinecraftVersion, ModLoader } from "../../../intefaces";
import {
  applyModpack,
  createModpack,
  deleteModpack,
  getMinecraftFolder,
  getModpacks,
  getVersions,
  openModpacksFolder,
  shareModpack,
  syncModpack,
  updateModpack,
} from "../../../tools";
import { useTranslation } from "react-i18next";
import quadrantLocale from "../../../i18n";
import Button from "../../core/Button";
import { AnimatePresence, motion } from "motion/react";
import {
  Description,
  Dialog,
  DialogBackdrop,
  DialogPanel,
  DialogTitle,
  Field,
  Fieldset,
  Input,
  Label,
  Select,
} from "@headlessui/react";
import "./Apply.css";
import { watch } from "@tauri-apps/plugin-fs";
import * as path from "@tauri-apps/api/path";
import {
  MdCheck,
  MdClear,
  MdCreate,
  MdDelete,
  MdEdit,
  MdFolder,
  MdInfo,
  MdShare,
  MdSync,
} from "react-icons/md";
import LoaderOptions from "../../shared/LoaderOption";
import { ContentContext } from "../../../intefaces";
import { listen } from "@tauri-apps/api/event";
import ModpackView from "../../shared/Pages/ModpackView";
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
  });
  const [originalModpackName, setOriginalModpackName] = useState("free");
  const [versions, setVersions] = useState<MinecraftVersion[]>([]);
  const [searchQuery, setSearchQuery] = useState<string>("");
  const context = useContext(ContentContext);

  // Get the modpacks for the first time and listen for changes to the Minecraft folder from the backend
  useEffect(() => {
    const effect = async () => {
      setModpacks(await getModpacks());
      setVersions(await getVersions());

      await watch(
        await path.join(await getMinecraftFolder(false)),
        async () => {
          await updateModpacks();
        },
        {
          delayMs: 50,
        }
      );
      await listen("quadrantShareSubmission", async (event: any) => {
        const usesLeft = event.payload.uses_left;
        context.setSnackbar({
          message: (
            <span className="flex">
              <MdCheck className="w-6 h-6 mx-2" />
              {t("copiedToClipboard", { amount: usesLeft })}
            </span>
          ),
          className: "bg-emerald-700 rounded-2xl",
          timeout: 5000,
        });
      });
    };
    effect();
  }, []);

  useEffect(() => {
    const effect = async () => {
      await updateModpacks();
    };
    effect();
  }, [searchQuery]);

  const updateModpacks = async () => {
    // console.log(searchQuery);
    const newModpacks = await getModpacks(true, searchQuery);

    if (newModpacks == modpacks) {
      return;
    }

    setModpacks(newModpacks);
  };

  return (
    <>
      <motion.div
        initial={{ y: 500, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        exit={{ y: 5000 }}
        className="flex flex-1 flex-col w-full "
      >
        <input
          placeholder={t("search")}
          className="p-4 input w-[95.5%] bg-slate-700 h-16 rounded-2xl self-center mx-16 my-8 text-center"
          onChange={(event) => {
            const query = event.target.value.toLowerCase().trim();
            setSearchQuery(query);
          }}
          autoComplete="off"
          value={searchQuery}
        ></input>
        <div className="flex flex-row justify-center w-fit self-center bg-slate-700 rounded-2xl my-4 p-2">
          <Button
            onClick={() => {
              const defaultModpack: LocalModpack = {
                name: "",
                version: versions[0].version,
                modLoader: ModLoader.Fabric,
                isApplied: false,
                lastSynced: 0,
                mods: [],
              };
              setIsDialogToCreate(true);
              setIsUpdateDialogOpen(true);
              setModpackToUpdate(defaultModpack);
            }}
            className="bg-emerald-600 mx-2 flex items-center align-middle w-fit hover:bg-emerald-700 rounded-2xl "
          >
            {t("createModpack")}
            <MdCreate className="w-6 h-6 mx-2" />
          </Button>
          <Button
            onClick={async () => {
              try {
                await deleteModpack("free");
              } catch (e) {}
              await createModpack(
                "free",
                versions[0].version,
                ModLoader.Unknown
              );
              await applyModpack("free");
              await updateModpacks();
            }}
            className="bg-yellow-600 flex items-center align-middle mx-2 w-fit hover:bg-yellow-700 rounded-2xl "
          >
            {t("clear")}
            <MdClear className="w-6 h-6 mx-2" />
          </Button>
          <Button
            onClick={async () => {
              await openModpacksFolder();
            }}
            className="bg-slate-800 flex items-center align-middle mx-2 w-fit hover:bg-slate-900 rounded-2xl "
          >
            {t("openModpacksFolder")}
            <MdFolder className="w-6 h-6 mx-2" />
          </Button>
        </div>
        <div className="bg-slate-800 rounded-2xl mx-6 mb-8">
          <AnimatePresence>
            {modpacks?.map((modpack, index) => {
              const date = new Date(modpack.lastSynced);

              const formattedDate = new Intl.DateTimeFormat(
                quadrantLocale.language,
                {
                  weekday: "long",
                  day: "2-digit",
                  month: "2-digit",
                  year: "2-digit",
                  hour: "2-digit",
                  minute: "2-digit",
                  hour12: false,
                }
              ).format(date);
              const dateString = t("localSyncDate", { date: formattedDate });
              return (
                <motion.div
                  initial={{ opacity: 0, y: 500 }}
                  animate={{ y: 50, opacity: 0.2 }}
                  whileHover={{ y: -5 }}
                  whileInView={{ y: 0, opacity: 1 }}
                  transition={{ duration: 0.125, ease: "linear" }}
                  exit={{
                    opacity: 0,
                    y: -500,
                  }}
                  key={index}
                  className="flex flex-col bg-slate-900 hover:bg-slate-950 p-4 rounded-2xl mx-5 my-5 h-max hover:shadow-lg hover:shadow-slate-950 "
                >
                  <h1 className="text-4xl font-extrabold max-w-56 w-56">
                    {modpack.name}
                  </h1>
                  <p className="text-md text-slate-400 hover:text-slate-50">
                    {modpack.version} | {modpack.modLoader} | {}
                    {t("modCount", { amount: modpack.mods.length })}{" "}
                    {modpack.lastSynced !== 0 && <span>| {dateString}</span>}
                  </p>
                  <div className="my-2.5 flex overflow-x-auto flex-wrap h-max flex-row items-center justify-start text-center w-full">
                    <Button
                      onClick={async () => {
                        if (modpack.isApplied) {
                          return;
                        }
                        try {
                          await applyModpack(modpack.name);
                          await updateModpacks();
                          context.setSnackbar({
                            message: (
                              <span className="flex">
                                <MdCheck className="w-6 h-6 mx-2" />
                                {t("setModpackSuccess")}
                              </span>
                            ),
                            className: "bg-emerald-700 rounded-2xl",
                            timeout: 5000,
                          });
                        } catch (e: any) {
                          console.error(e);
                          context.setSnackbar({
                            message: t("setModpackFailed"),
                            className: "bg-red-700 rounded-2xl",
                            timeout: 5000,
                          });
                        }
                      }}
                      className={
                        modpack.isApplied
                          ? "flex items-center self-center bg-emerald-900 cursor-default w-max h-16 justify-center m-2"
                          : "flex items-center self-center bg-emerald-600 hover:bg-emerald-800 w-max h-16 justify-center m-2"
                      }
                    >
                      {modpack.isApplied ? t("applied") : t("apply")}
                      <MdCheck className="w-6 h-6 mx-2" />
                    </Button>
                    <Button
                      onClick={async () => {
                        try {
                          await shareModpack(modpack.name);
                        } catch (e: any) {
                          console.error(e);
                          context.setSnackbar({
                            message: t(e),
                            className: "bg-red-700 rounded-2xl",
                            timeout: 5000,
                          });
                        }
                      }}
                      className={
                        "flex items-center self-center bg-blue-600 hover:bg-blue-800 m-2 w-max h-16 justify-center"
                      }
                    >
                      {t("share")}
                      <MdShare className="w-6 h-6 mx-2" />
                    </Button>
                    <Button
                      onClick={async () => {
                        try {
                          await syncModpack(modpack, true);
                          context.setSnackbar({
                            message: (
                              <span className="flex">
                                <MdCheck className="w-6 h-6 mx-2" />
                                {t("modpackUpdated")}
                              </span>
                            ),
                            className: "bg-emerald-700 rounded-2xl",
                            timeout: 5000,
                          });
                          await updateModpacks();
                        } catch (e: any) {
                          console.error(e);
                          context.setSnackbar({
                            message: t(e),
                            className: "bg-red-700 rounded-2xl",
                            timeout: 5000,
                          });
                        }
                      }}
                      className={
                        "flex items-center self-center bg-lime-600 hover:bg-lime-800 m-2 w-max h-16 justify-center"
                      }
                    >
                      {t("sync")}
                      <MdSync className="w-6 h-6 ml-2" />
                    </Button>
                    <Button
                      onClick={async () => {
                        setIsUpdateDialogOpen(true);
                        setIsDialogToCreate(false);
                        setOriginalModpackName(
                          JSON.parse(JSON.stringify(modpack.name))
                        );
                        setModpackToUpdate(modpack);
                      }}
                      className={
                        "flex items-center self-center bg-indigo-500 hover:bg-indigo-700 m-2 w-max h-16 justify-center"
                      }
                    >
                      {t("update")}
                      <MdEdit className="w-6 h-6 mx-2" />
                    </Button>
                    <Button
                      onClick={async () => {
                        try {
                          await deleteModpack(modpack.name);
                          await updateModpacks();
                          context.setSnackbar({
                            message: <MdDelete className="w-6 h-6 mx-2" />,
                            className: "bg-emerald-700 rounded-2xl",
                            timeout: 5000,
                          });
                        } catch (e: any) {
                          console.error(e);
                          context.setSnackbar({
                            message: t("unknown"),
                            className: "bg-red-700 text-slate-950 rounded-2xl",
                            timeout: 5000,
                          });
                        }
                      }}
                      className={
                        "flex items-center self-center bg-red-500 hover:bg-red-700  w-max h-16 m-2 justify-center"
                      }
                    >
                      {t("delete")}
                      <MdDelete className="w-6 h-6 mx-2" />
                    </Button>
                    <Button
                      onClick={async () => {
                        const randomString = Math.random()
                          .toString(36)
                          .substring(2, 10);
                        context.changeContent({
                          name: modpack.name + randomString,
                          title: modpack.name,
                          style: "",
                          main: false,
                          icon: <></>,
                          content: (
                            <ModpackView
                              name={modpack.name}
                              isApplied={modpack.isApplied}
                              lastSynced={modpack.lastSynced}
                              modLoader={modpack.modLoader}
                              mods={modpack.mods}
                              version={modpack.version}
                            ></ModpackView>
                          ),
                        });
                      }}
                      className={
                        "flex items-center self-center bg-slate-500 hover:bg-slate-700 w-max m-2 h-16 justify-center"
                      }
                    >
                      {t("details")}
                      <MdInfo className="w-6 h-6 mx-2" />
                    </Button>
                  </div>
                </motion.div>
              );
            })}
          </AnimatePresence>
        </div>
        <Dialog
          open={isUpdateDialogOpen}
          onClose={() => setIsUpdateDialogOpen(false)}
          className="relative z-50"
        >
          <DialogBackdrop className="fixed inset-0 bg-slate-950/30 " />
          <AnimatePresence>
            <motion.div
              initial={{ opacity: 0, y: -500, scale: 0.125 }}
              animate={{ opacity: 1, y: 0, scale: 1.25 }}
              exit={{ opacity: 0, y: 500 }}
              className="fixed inset-0 flex w-screen items-center justify-center p-4"
            >
              <DialogPanel className="max-w-xl space-y-4 rounded-2xl bg-slate-800 p-8">
                <DialogTitle className="font-black text-2xl">
                  {isDialogToCreate ? t("createModpack") : t("update")}
                </DialogTitle>
                <Description>
                  {isDialogToCreate
                    ? t("createModpack")
                    : t("updateModpackDetails")}
                </Description>
                <Fieldset>
                  <Field>
                    <Label className="block my-2 font-bold">
                      {t("chooseVersion")}
                    </Label>
                    <Select
                      className="bg-slate-700 w-full p-2 rounded-2xl font-semibold hover:bg-slate-600"
                      name="version"
                      value={modpackToUpdate.version}
                      onChange={(newValue) => {
                        let modpack: LocalModpack = JSON.parse(
                          JSON.stringify(modpackToUpdate)
                        );
                        modpack.version = newValue.target.value;
                        setModpackToUpdate(modpack);
                      }}
                    >
                      {versions.map((version) => {
                        return (
                          <option
                            value={version.version}
                            defaultChecked={
                              version.version == modpackToUpdate.version
                            }
                            className="rounded-2xl font-semibold"
                            key={version.version}
                          >
                            {version.version}
                          </option>
                        );
                      })}
                    </Select>
                  </Field>
                  <Field>
                    <Label className="block my-2 font-bold">
                      {t("choosePreferredAPI")}
                    </Label>
                    <Select
                      className="bg-slate-700 w-full p-2 rounded-2xl font-semibold hover:bg-slate-600"
                      name="modLoader"
                      value={modpackToUpdate.modLoader}
                      onChange={(newValue) => {
                        let modpack: LocalModpack = JSON.parse(
                          JSON.stringify(modpackToUpdate)
                        );
                        let loaderString = newValue.target.value;
                        let loader = ModLoader.Unknown;
                        if (loaderString.toLowerCase().includes("fabric")) {
                          loader = ModLoader.Fabric;
                        } else if (
                          loaderString.toLowerCase().includes("neoforge")
                        ) {
                          loader = ModLoader.NeoForge;
                        } else if (
                          loaderString.toLowerCase().includes("forge")
                        ) {
                          loader = ModLoader.Forge;
                        } else if (
                          loaderString.toLowerCase().includes("rift")
                        ) {
                          loader = ModLoader.Rift;
                        } else if (
                          loaderString.toLowerCase().includes("quilt")
                        ) {
                          loader = ModLoader.Quilt;
                        }
                        modpack.modLoader = loader;
                        setModpackToUpdate(modpack);
                      }}
                    >
                      <LoaderOptions loader={modpackToUpdate.modLoader} />
                    </Select>
                  </Field>
                  <Field>
                    <Label className="block my-2 font-bold">
                      {isDialogToCreate ? t("name") : t("chooseModpack")}
                    </Label>
                    <Input
                      className="bg-slate-700 focus:bg-slate-600 focus: focus:border-2 focus:border-slate-500 w-full p-2 rounded-2xl font-semibold hover:bg-slate-600"
                      name="modLoader"
                      type="text"
                      value={modpackToUpdate.name}
                      autoComplete="off"
                      onChange={(newValue) => {
                        // Deep copy modpackToUpdate
                        let modpack: LocalModpack = JSON.parse(
                          JSON.stringify(modpackToUpdate)
                        );
                        let newName = newValue.target.value.replace(
                          /[<>:"/\\|?*]/,
                          ""
                        );

                        modpack.name = newName;
                        setModpackToUpdate(modpack);
                      }}
                    ></Input>
                  </Field>
                </Fieldset>
                <div className="flex gap-4">
                  <Button
                    className="bg-indigo-500  hover:bg-indigo-700"
                    onClick={async () => {
                      if (isDialogToCreate) {
                        if (modpackToUpdate.name.trim().length === 0) {
                          setIsUpdateDialogOpen(false);
                          return;
                        }
                        if (modpackToUpdate.modLoader === ModLoader.Unknown) {
                          setIsUpdateDialogOpen(false);
                          return;
                        }
                        try {
                          await createModpack(
                            modpackToUpdate.name,
                            modpackToUpdate.version,
                            modpackToUpdate.modLoader
                          );
                          context.setSnackbar({
                            message:
                              modpackToUpdate.name +
                              " | " +
                              modpackToUpdate.version +
                              " | " +
                              modpackToUpdate.modLoader,
                            className: "bg-emerald-700 rounded-2xl",
                            timeout: 5000,
                          });
                          await updateModpacks();
                        } catch (e: any) {
                          console.error(e);
                          context.setSnackbar({
                            message: t("invalidData"),
                            className: "bg-red-700 text-slate-950 rounded-2xl",
                            timeout: 5000,
                          });
                        }
                      } else {
                        try {
                          await updateModpack(
                            originalModpackName,
                            modpackToUpdate
                          );
                          await updateModpacks();
                          context.setSnackbar({
                            message:
                              modpackToUpdate.name +
                              " | " +
                              modpackToUpdate.version +
                              " | " +
                              modpackToUpdate.modLoader,
                            className: "bg-emerald-700 rounded-2xl",
                            timeout: 5000,
                          });
                        } catch (e: any) {
                          console.error(e);
                          context.setSnackbar({
                            message: t("invalidData"),
                            className: "bg-red-700 text-slate-950 rounded-2xl",
                            timeout: 5000,
                          });
                        }
                      }
                      setIsUpdateDialogOpen(false);
                    }}
                  >
                    {isDialogToCreate ? t("createModpack") : t("update")}
                  </Button>
                  <Button
                    className="bg-slate-600  hover:bg-slate-700"
                    onClick={() => setIsUpdateDialogOpen(false)}
                  >
                    {t("cancel")}
                  </Button>
                </div>
              </DialogPanel>
            </motion.div>
          </AnimatePresence>
        </Dialog>
        <div className="h-1"></div>
      </motion.div>
    </>
  );
}
