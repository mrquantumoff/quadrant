/** @format */

import { useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  IMod,
  LocalModpack,
  MinecraftVersion,
  ModLoader,
  ModSource,
  ModType,
} from "../../../intefaces";
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
import { createDesktopStore } from "../../../desktop";
import {
  loaderProvidersFromSettings,
  loaderSupportsProvider,
  ModLoaderProvider,
} from "../../../modLoaders";

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
  const [loaderProviders, setLoaderProviders] = useState<ModLoaderProvider[]>(
    loaderProvidersFromSettings(true, true),
  );
  const configRef = useRef(createDesktopStore("config.json"));
  const configStore = configRef.current;
  const search = async (forceSearch: boolean = false) => {
    if (searchQuery.trim() === "" && !forceSearch) {
      return;
    }

    setMods([]);
    setAllResults([]);
    setPage(1);

    const query = searchQuery.toLowerCase();

    const [curseforge, modrinth] = await Promise.all([
      configStore.get<boolean>("curseforge"),
      configStore.get<boolean>("modrinth"),
    ]);
    setLoaderProviders(loaderProvidersFromSettings(curseforge, modrinth));

    console.log("Filter: " + filter);

    const requests: Promise<IMod[]>[] = [];

    // Filtered searches only query providers that can satisfy the selected loader.
    if (
      curseforge &&
      (!filter || loaderSupportsProvider(loader, ModSource.CurseForge))
    ) {
      const curseforgeArgs = {
        filterOn: filter,
        query: query,
        source: ModSource.CurseForge,
      };
      requests.push(
        searchMods({ ...curseforgeArgs, modType: ModType.Mod.toString() }),
        searchMods({
          ...curseforgeArgs,
          modType: ModType.ResourcePack.toString(),
        }),
        searchMods({
          ...curseforgeArgs,
          modType: ModType.ShaderPack.toString(),
        }),
      );
    }

    if (
      modrinth &&
      (!filter || loaderSupportsProvider(loader, ModSource.Modrinth))
    ) {
      const modrinthArgs = {
        filterOn: filter,
        query: query,
        source: ModSource.Modrinth,
      };
      requests.push(
        searchMods({ ...modrinthArgs, modType: ModType.Mod.toString() }),
        searchMods({
          ...modrinthArgs,
          modType: ModType.ResourcePack.toString(),
        }),
        searchMods({
          ...modrinthArgs,
          modType: ModType.ShaderPack.toString(),
        }),
      );
    }

    const results = await Promise.all(requests);
    let newMods = results.flat();

    if (newMods.length === 0) {
      newMods = [
        {
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
          selectable: false,
          selectUrl: null,
          modpack: null,
        },
      ];
    } else {
      newMods.sort((a, b) => b.downloadCount - a.downloadCount);
    }

    const firstFifty = newMods.length > 50 ? newMods.slice(0, 50) : newMods;
    setMods(firstFifty);
    setAllResults(newMods);
  };
  const effect = async () => {
    const [
      availableVersions,
      availableModpacks,
      curseForgeEnabled,
      modrinthEnabled,
    ] = await Promise.all([
      getVersions(),
      getModpacks(),
      configStore.get<boolean>("curseforge"),
      configStore.get<boolean>("modrinth"),
    ]);

    setVersions(availableVersions);
    setModpacks(availableModpacks);
    setLoaderProviders(
      loaderProvidersFromSettings(curseForgeEnabled, modrinthEnabled),
    );

    const [lastVersion, lastLoader, lastUsedModpack] = await Promise.all([
      configStore.get<string>("lastUsedVersion"),
      configStore.get<string>("lastUsedAPI"),
      configStore.get<string>("lastUsedModpack"),
    ]);

    const defaultModpack = availableModpacks[0];

    const resolvedVersion = lastVersion ?? defaultModpack?.version ?? "";
    const resolvedLoader = lastLoader ?? defaultModpack?.modLoader ?? "";
    const resolvedModpack = lastUsedModpack ?? defaultModpack?.name ?? "";

    setVersion(resolvedVersion);
    setLoader(resolvedLoader);
    setModpack(resolvedModpack);

    if (lastVersion === undefined && defaultModpack?.version) {
      await configStore.set("lastUsedVersion", defaultModpack.version);
    }
    if (lastLoader === undefined && defaultModpack?.modLoader) {
      await configStore.set("lastUsedAPI", defaultModpack.modLoader);
    }
    if (lastUsedModpack === undefined && defaultModpack?.name) {
      await configStore.set("lastUsedModpack", defaultModpack.name);
    }
    if (
      (lastVersion === undefined && defaultModpack?.version) ||
      (lastLoader === undefined && defaultModpack?.modLoader) ||
      (lastUsedModpack === undefined && defaultModpack?.name)
    ) {
      await configStore.save();
    }

    await search(true);
  };
  useEffect(() => {
    effect().catch(console.error);
  }, []);

  useEffect(() => {
    search(true);
  }, [filter]);

  const MotionPopoverButton = motion.create(PopoverButton);

  return (
    <>
      <motion.div
        initial={{ y: 24, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        exit={{ y: 24, opacity: 0 }}
        className="flex flex-col w-full h-full justify-start items-center content-main transform-gpu [backface-visibility:hidden] [will-change:transform,opacity]"
      >
        <div className="h-min w-full">
          <AnimatePresence>
            {filter && (
              <motion.div
                initial={{ y: -24 }}
                animate={{ y: 0 }}
                exit={{ y: 16, opacity: 0 }}
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
            className="flex flex-1 items-center justify-center mb-8 h-fit w-[95%] mx-8 my-2 "
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
            <div className="flex flex-col h-fit">
              <Button
                onClick={search}
                animate
                className="flex items-center my-2 justify-center hover:text-sky-950 self-center bg-sky-800 hover:bg-sky-400 h-min"
              >
                <MdSearch className=""></MdSearch>
                {t("search")}
              </Button>
              <Popover className="relative">
                {({ open }) => {
                  return (
                    <>
                      <MotionPopoverButton
                        whileHover={{ y: -5, scale: 1.1 }}
                        whileTap={{ scale: 0.9 }}
                        className={
                          "flex w-full items-center bg-slate-600 my-2 rounded-4xl focus:outline-none hover:bg-slate-700 font-bold p-2 self-start"
                        }
                      >
                        <MdFilterAlt />
                        {t("filter")}
                      </MotionPopoverButton>
                      <AnimatePresence>
                        {open && (
                          <PopoverPanel
                            anchor="bottom"
                            className="bg-slate-900 border-2 mt-8 border-slate-700 p-8 rounded-4xl flex flex-col w-max transform-gpu [backface-visibility:hidden] [will-change:transform,opacity]"
                            static
                            as={motion.div}
                            initial={{
                              opacity: 0,
                              scale: 0.98,
                              x: 24,
                              y: -16,
                            }}
                            animate={{ opacity: 1, scale: 1, x: 0, y: 0 }}
                            exit={{ opacity: 0, scale: 0.98, x: 24, y: -16 }}
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
                                    const newVersion = e.target.value;
                                    setVersion(newVersion);
                                    await configStore.set(
                                      "lastUsedVersion",
                                      newVersion,
                                    );
                                    await configStore.save();
                                  }}
                                >
                                  {versions.map((versionOption) => {
                                    return (
                                      <option
                                        value={versionOption.version}
                                        className="rounded-4xl font-semibold"
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
                                    const selectedLoader = e.target.value;
                                    setLoader(selectedLoader);

                                    await configStore.set(
                                      "lastUsedAPI",
                                      selectedLoader,
                                    );
                                    await configStore.save();
                                  }}
                                  value={loader}
                                  autoComplete="off"
                                >
                                  <LoaderOptions
                                    loader={loader}
                                    providers={loaderProviders}
                                  />
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
                                    const selectedModpack = modpacks.find(
                                      (i) => i.name === e.target.value,
                                    );
                                    if (!selectedModpack) {
                                      return;
                                    }

                                    await configStore.set(
                                      "lastUsedModpack",
                                      selectedModpack.name,
                                    );
                                    await configStore.set(
                                      "lastUsedVersion",
                                      selectedModpack.version,
                                    );
                                    await configStore.set(
                                      "lastUsedAPI",
                                      selectedModpack.modLoader,
                                    );
                                    await configStore.save();
                                    setModpack(selectedModpack.name);
                                    setLoader(selectedModpack.modLoader);
                                    setVersion(selectedModpack.version);
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
                                  as={motion.button}
                                  whileHover={{ y: -5, scale: 1.1 }}
                                  whileTap={{ scale: 0.9 }}
                                  className={
                                    "p-2 font-extrabold rounded-4xl mx-2 flex flex-1 h-full items-center bg-emerald-600 hover:bg-emerald-800 mt-8"
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
                                  as={motion.button}
                                  whileHover={{ y: -5, scale: 1.1 }}
                                  whileTap={{ scale: 0.9 }}
                                  className={
                                    "p-2 font-extrabold rounded-4xl mx-2 flex flex-1 h-full items-center bg-slate-600 hover:bg-slate-800 mt-8"
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
        </div>
        <div className="h-max flex items-center place-content-center">
          <AnimatePresence>
            {mods.length !== 0 ? (
              <div className="bg-slate-800 items-center align-middle justify-center rounded-4xl mr-4 ml-2 mb-12 ">
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
                      initial={{ opacity: 0, y: 16 }}
                      animate={{ opacity: 1, y: 0 }}
                      whileHover={{ opacity: 1 }}
                      exit={{ opacity: 0, y: 16 }}
                      className="flex flex-col mb-8 items-center justify-center transform-gpu [backface-visibility:hidden] [will-change:transform,opacity]"
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
                                : allResults.length,
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
              <div className="bg-slate-800 rounded-4xl self-center p-8 items-center justify-center">
                <CircularProgress></CircularProgress>
              </div>
            )}
          </AnimatePresence>
        </div>
      </motion.div>
    </>
  );
}
