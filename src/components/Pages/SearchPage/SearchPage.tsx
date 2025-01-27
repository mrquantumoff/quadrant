import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  IMod,
  LocalModpack,
  MinecraftVersion,
  ModLoader,
  ModSource,
  ModType,
} from "../../../intefaces";
import { load } from "@tauri-apps/plugin-store";
import { getModpacks, getVersions, searchMods } from "../../../tools";
import Mod from "../../shared/Mod";
import Button from "../../core/Button";
import "./SearchPage.css";
import {
  MdArrowDownward,
  MdCancel,
  MdCheck,
  MdFilterAlt,
  MdSearch,
} from "react-icons/md";
import CircularProgress from "../../core/CircularProgress";
import { AnimatePresence, motion } from "motion/react";
import {
  CloseButton,
  Field,
  Fieldset,
  Input,
  Label,
  Popover,
  PopoverButton,
  PopoverPanel,
  Select,
} from "@headlessui/react";
import LoaderOptions from "../../shared/LoaderOption";

export default function SearchPage() {
  const [searchQuery, setSearchQuery] = useState("");
  const { t } = useTranslation();
  const [mods, setMods] = useState<IMod[]>([]);
  const [allResults, setAllResults] = useState<IMod[]>([]);
  const [page, setPage] = useState(1);
  const [filter, setFilter] = useState<boolean>(false);
  const [versions, setVersions] = useState<MinecraftVersion[]>([]);
  const [modpacks, setModpacks] = useState<LocalModpack[]>([]);
  const [version, setVersion] = useState<string>("");
  const [modpack, setModpack] = useState<string>("");
  const [loader, setLoader] = useState<string>(ModLoader.Unknown);
  const search = async (forceSearch: boolean = false) => {
    const config = await load("config.json");

    if (searchQuery.trim() === "" && !forceSearch) {
      return;
    }

    setMods([]);
    setAllResults([]);
    setPage(1);

    const query = searchQuery.toLowerCase();

    const curseforge = await config.get<boolean>("curseforge");
    const modrinth = await config.get<boolean>("modrinth");

    let newMods: IMod[] = [];

    console.log("Filter: " + filter);

    if (curseforge) {
      newMods = [
        ...newMods,
        ...(await searchMods({
          source: ModSource.CurseForge,
          filterOn: filter,
          modType: ModType.Mod.toString(),
          query: query,
        })),
      ];
      newMods = [
        ...newMods,
        ...(await searchMods({
          source: ModSource.CurseForge,

          filterOn: filter,
          modType: ModType.ResourcePack.toString(),
          query: query,
        })),
      ];
      newMods = [
        ...newMods,
        ...(await searchMods({
          source: ModSource.CurseForge,
          filterOn: filter,
          modType: ModType.ShaderPack.toString(),
          query: query,
        })),
      ];
    }
    if (modrinth) {
      newMods = [
        ...newMods,
        ...(await searchMods({
          source: ModSource.Modrinth,
          filterOn: filter,
          modType: ModType.Mod.toString(),
          query: query,
        })),
      ];
      newMods = [
        ...newMods,
        ...(await searchMods({
          source: ModSource.Modrinth,
          filterOn: filter,
          modType: ModType.ResourcePack.toString(),
          query: query,
        })),
      ];
      newMods = [
        ...newMods,
        ...(await searchMods({
          source: ModSource.Modrinth,
          filterOn: filter,
          modType: ModType.ShaderPack.toString(),
          query: query,
        })),
      ];
    }
    if (newMods.length === 0) {
      newMods.push({
        autoinstallable: false,
        downloadCount: 0,
        deleteable: false,
        description: t("-"),
        downloadable: false,
        id: "",
        license: "",
        modIconUrl: "",
        modType: ModType.Mod,
        name: "-",
        showPreviousVersion: false,
        slug: "",
        source: ModSource.Online,
        thumbnailUrls: [],
        url: "https://mrquantumoff.dev",
        version: "",
        newVersion: null,
      });
    }
    newMods.sort((a, b) => b.downloadCount - a.downloadCount);
    const firstFifty = newMods.length > 50 ? newMods.slice(0, 50) : newMods;
    setMods(firstFifty);
    setAllResults(newMods);
  };
  const effect = async () => {
    const config = await load("config.json");

    const lastVersion = await config.get<string>("lastUsedVersion");
    const lastLoader = await config.get<string>("lastUsedAPI");
    const lastModpack = await config.get<string>("lastUsedModpack");

    setVersions(await getVersions());
    setModpacks(await getModpacks());
    const modpacks = await getModpacks();
    setVersion(lastVersion ?? modpacks[0].version ?? "");
    setLoader(lastLoader ?? modpacks[0].modLoader ?? "");
    setModpack(lastModpack ?? modpacks[0].name ?? "");
    if (lastVersion === undefined) {
      await config.set("lastUsedVersion", modpacks[0].version ?? "");
    }
    if (lastLoader === undefined) {
      await config.set("lastUsedAPI", modpacks[0].modLoader ?? "");
      setLoader(modpacks[0].modLoader ?? "");
    }
    if (lastModpack === undefined) {
      await config.set("lastUsedModpack", modpacks[0].name ?? "");
      setModpack(modpacks[0].name ?? "");
    }
    await config.save();

    await search(true);
  };
  useEffect(() => {
    effect().catch(console.error);
  }, []);

  useEffect(() => {
    search(true);
  }, [filter]);
  return (
    <>
      <motion.div
        initial={{ y: 500, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        exit={{ y: 5000 }}
        className="flex flex-1 flex-col w-full h-full justify-start items-center content-main "
      >
        <AnimatePresence>
          {filter && (
            <motion.div
              initial={{ y: -500 }}
              animate={{ y: 0 }}
              exit={{ y: 50, opacity: 0 }}
              className="items-center font-bold text-center mt-8"
            >
              {modpack} | {version} | {loader}
            </motion.div>
          )}
        </AnimatePresence>
        <form
          onSubmit={async (e) => {
            e.preventDefault();
            search();
          }}
          className="flex flex-1 items-center justify-center mb-8 w-[95%] mx-8 my-2 "
        >
          <Input
            placeholder={t("searchForMods")}
            className="w-full input h-16 self-center mr-4 text-center"
            onChange={(event) => {
              const query = event.target.value;
              setSearchQuery(query);
            }}
            autoComplete="off"
            value={searchQuery}
            onSubmit={async () => {
              search();
            }}
          ></Input>
          <div className="flex flex-col">
            <Button
              onClick={search}
              className="flex items-center my-2 justify-center hover:text-sky-950 self-center bg-sky-800 hover:bg-sky-400 h-fit"
            >
              <MdSearch className=""></MdSearch>
              {t("search")}
            </Button>
            <Popover className="relative">
              {({ open }) => {
                return (
                  <>
                    <PopoverButton
                      className={
                        "flex w-full items-center bg-slate-600 my-2 rounded-2xl focus:outline-none hover:bg-slate-700 font-bold p-2 self-start"
                      }
                    >
                      <MdFilterAlt />
                      {t("filter")}
                    </PopoverButton>
                    <AnimatePresence>
                      {open && (
                        <PopoverPanel
                          anchor="bottom"
                          className="bg-slate-900 border-2 mt-8 border-slate-700 p-8 rounded-2xl flex flex-col w-max"
                          static
                          as={motion.div}
                          initial={{
                            opacity: 0,
                            scale: 0.125,
                            x: 200,
                            y: -50,
                          }}
                          animate={{ opacity: 1, scale: 1, x: 0, y: 0 }}
                          exit={{ opacity: 0, scale: 0.125, x: 200, y: -50 }}
                        >
                          <Fieldset>
                            <Field>
                              <Label className="block my-2 font-bold">
                                {t("chooseVersion")}
                              </Label>
                              <Select
                                className="w-full input"
                                name="version"
                                autoComplete="off"
                                value={version}
                                onChange={async (e) => {
                                  e.preventDefault();
                                  setVersion(e.target.value);

                                  const config = await load("config.json");

                                  await config.set(
                                    "lastUsedVersion",
                                    e.target.value
                                  );
                                  setVersion(e.target.value);
                                }}
                              >
                                {versions.map((versionOption) => {
                                  return (
                                    <option
                                      value={versionOption.version}
                                      className="rounded-2xl font-semibold"
                                      key={versionOption.version}
                                    >
                                      {versionOption.version}
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
                                className="w-full input"
                                name="modLoader"
                                onChange={async (e) => {
                                  e.preventDefault();
                                  setLoader(e.target.value);

                                  const config = await load("config.json");

                                  await config.set(
                                    "lastUsedAPI",
                                    e.target.value
                                  );
                                  await config.save();
                                }}
                                value={loader}
                                autoComplete="off"
                              >
                                <LoaderOptions loader={loader} />
                              </Select>
                            </Field>
                            <Field>
                              <Label className="block my-2 font-bold">
                                {t("chooseModpack")}
                              </Label>
                              <Select
                                className="w-full input"
                                name="modpack"
                                autoComplete="off"
                                value={modpack}
                                onChange={async (e) => {
                                  e.preventDefault();
                                  const modpack = modpacks.filter(
                                    (i) => i.name === e.target.value
                                  )[0];
                                  const config = await load("config.json");

                                  await config.set(
                                    "lastUsedModpack",
                                    modpack.name
                                  );
                                  await config.set(
                                    "lastUsedVersion",
                                    modpack.version
                                  );
                                  await config.set(
                                    "lastUsedAPI",
                                    modpack.modLoader
                                  );
                                  await config.save();
                                  setModpack(modpack.name);
                                  setLoader(modpack.modLoader);
                                  setVersion(modpack.version);
                                  setFilter(true);
                                }}
                              >
                                {modpacks.map((modpack) => (
                                  <option
                                    value={modpack.name}
                                    key={modpack.name}
                                  >
                                    {modpack.name} | {modpack.modLoader} |{" "}
                                    {modpack.version}
                                  </option>
                                ))}
                              </Select>
                            </Field>
                            <div className="flex flex-1 items-center justify-center">
                              <CloseButton
                                className={
                                  "p-2 font-extrabold rounded-2xl mx-2 flex flex-1 h-full items-center bg-emerald-600 hover:bg-emerald-800 mt-8"
                                }
                                onClick={() => {
                                  setFilter(true);
                                }}
                              >
                                <MdCheck className="w-6 h-6 mr-2 self-center" />
                                {t("apply")}
                              </CloseButton>
                              <CloseButton
                                onClick={() => {
                                  setFilter(false);
                                }}
                                className={
                                  "p-2 font-extrabold rounded-2xl mx-2 flex flex-1 h-full items-center bg-slate-600 hover:bg-slate-800 mt-8"
                                }
                              >
                                <MdCancel className="w-6 h-6 mr-2 self-center" />
                                {t("cancel")}
                              </CloseButton>
                            </div>
                          </Fieldset>
                        </PopoverPanel>
                      )}
                    </AnimatePresence>
                  </>
                );
              }}
            </Popover>
          </div>
        </form>

        <AnimatePresence>
          {mods.length !== 0 ? (
            <div className="bg-slate-800 items-center align-middle justify-center rounded-2xl mr-4 ml-2 mb-12 ">
              <div className="grid grid-cols-3 mb-0 2xl:grid-cols-4 gap-6 p-4">
                {mods.map((mod, index) => {
                  return (
                    <Mod
                      key={index}
                      className=" "
                      mod={mod}
                      modpack={undefined}
                    ></Mod>
                  );
                })}
              </div>
              <AnimatePresence>
                {allResults.length > 50 * page && (
                  <motion.div
                    initial={{ opacity: 0, scale: 0.125 }}
                    whileInView={{ opacity: 1, scale: 1 }}
                    whileHover={{ opacity: 1 }}
                    exit={{ y: 500 }}
                    className="flex flex-col mb-8 items-center justify-center"
                  >
                    <Button
                      onClick={() => {
                        const isThereNextPage =
                          allResults.length > 50 * (page + 1);
                        setMods([
                          ...mods,
                          ...allResults.slice(
                            50 * page,
                            isThereNextPage
                              ? 50 * (page + 1)
                              : allResults.length
                          ),
                        ]);
                        setPage(page + 1);
                      }}
                      className=" bg-emerald-600  p-4  hover:bg-emerald-700 mt-8"
                    >
                      <MdArrowDownward className="w-6 h-6 self-center" />
                    </Button>
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          ) : (
            <div className="bg-slate-800 rounded-2xl w-min p-8 mr-4 ml-2 mb-12 flex flex-1 items-center justify-center">
              <CircularProgress></CircularProgress>
            </div>
          )}
        </AnimatePresence>
      </motion.div>
    </>
  );
}
