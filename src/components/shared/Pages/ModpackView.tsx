import quadrantLocale from "../../../i18n";
import {
  FetchedIdentifiedMod,
  IMod,
  LocalModpack,
  ModpackViewContext,
  ModSource,
  ModType,
} from "../../../intefaces";
import { useEffect, useState } from "react";
import { getMod, getModUpdate, identifyUnknownMods } from "../../../tools";
import Mod from "../Mod";
import { useTranslation } from "react-i18next";
import CircularProgress from "../../core/CircularProgress";

import Button from "../../core/Button";
import { MdPermIdentity, MdUpdate } from "react-icons/md";

export default function ModpackView(modpack: LocalModpack) {
  const localMods = modpack.mods;
  const [mods, setMods] = useState<IMod[]>([]);
  const [updates, setUpdates] = useState<IMod[]>([]);
  const [toIdentify, setToIdentify] = useState<FetchedIdentifiedMod[]>([]);
  const [showUpdates, setShowUpdates] = useState(false);
  const [showIdentify, setShowIdentify] = useState(false);
  const [modCount, setModCount] = useState(mods.length);

  const updateModpackDetails = async () => {
    setMods([]);
    if (!showUpdates) {
      setModCount(0);
    }
    if (showIdentify) {
      await getIdentifiedMods();
    }
    let newMods: IMod[] = [];
    await localMods.forEach(async (mod) => {
      const fullMod = await getMod(
        {
          id: mod.id,
          deletable: true,
          downloadable: false,
          modpack: modpack.name,
          modLoader: modpack.modLoader,
          versionTarget: "",
          showPreviousVersion: false,
          selectable: false,
          selectUrl: null,
        },
        mod.source
      );
      newMods.push(fullMod);
      newMods.sort((a, b) => b.downloadCount - a.downloadCount);

      setMods(newMods);
      if (!showUpdates) {
        setModCount(newMods.length);
      }
    });

    setMods(newMods);
    if (!showUpdates) {
      setModCount(newMods.length);
    }
    if (newMods.length === 0) {
      setMods([
        {
          autoinstallable: false,
          deleteable: false,
          description: "-",
          downloadCount: 0,
          id: "-",
          modIconUrl:
            "https://raw.githubusercontent.com/mrquantumoff/quadrant/master/assets/icons/logo.png",
          downloadable: false,
          name: "-",
          source: ModSource.Online,
          thumbnailUrls: [],
          url: "",
          modType: ModType.Mod,
          license: "-",
          showPreviousVersion: false,
          slug: "-",
          version: "",
          newVersion: null,
          modpack: "",
          selectable: false,
          selectUrl: null,
        },
      ]);
    }
  };

  const checkForUpdates = async () => {
    setUpdates([]);
    let newUpdates: IMod[] = [];
    // Deep copy the mods
    const normalMods: IMod[] = JSON.parse(JSON.stringify(mods));
    for (const mod of normalMods) {
      try {
        let update = await getModUpdate(
          mod,
          modpack.version,
          modpack.modLoader,
          modpack.name
        );
        if (update === null) {
          console.log("No update found");
          continue;
        }
        newUpdates.push(update);
        newUpdates.sort((a, b) => b.downloadCount - a.downloadCount);
      } catch (e) {
        console.log("Error while checking for updates: " + e);
      }
    }

    setUpdates(newUpdates);
    if (newUpdates.length === 0) {
      setShowUpdates(false);
      setModCount(mods.length);
    } else {
      setModCount(updates.filter((mod) => mod.downloadable === true).length);
    }
  };

  const getIdentifiedMods = async () => {
    console.log("Getting mods");
    const newMods = await identifyUnknownMods(modpack.name);
    let newFetchedMods: FetchedIdentifiedMod[] = [];
    console.log("New mods: " + newMods);
    for (const mod of newMods) {
      console.log(mod);
      if (
        newFetchedMods.filter(
          (fetchedMod) => fetchedMod.fileName === mod.file_name
        ).length === 0
      ) {
        console.log("Adding a new mod from source.");
        newFetchedMods.push({
          proposedMods: [
            await getMod(
              {
                deletable: false,
                id: mod.installed_mod.id,
                downloadable: false,
                showPreviousVersion: false,
                versionTarget: "",
                selectable: true,
                selectUrl: mod.installed_mod.downloadUrl,
                modLoader: modpack.modLoader,
                modpack: modpack.name,
              },
              mod.installed_mod.source
            ),
          ],
          fileName: mod.file_name,
        });
      } else {
        console.log("Adding mod from an alternate source.");
        const index = newFetchedMods.findIndex(
          (fMod) => fMod.fileName === mod.file_name
        );
        newFetchedMods[index].proposedMods.push(
          await getMod(
            {
              deletable: false,
              id: mod.installed_mod.id,
              downloadable: false,
              showPreviousVersion: false,
              versionTarget: "",
              selectable: true,
              selectUrl: mod.installed_mod.downloadUrl,
              modLoader: modpack.modLoader,
              modpack: modpack.name,
            },
            mod.installed_mod.source
          )
        );
      }
    }
    if (newFetchedMods.length === 0) {
      setToIdentify([]);
      setShowIdentify(false);
    }
    setToIdentify(newFetchedMods);
  };

  const { t } = useTranslation();
  useEffect(() => {
    const effect = async () => {
      await updateModpackDetails();
    };

    effect().catch((e) => console.error(e));
  }, []);

  useEffect(() => {
    if (showIdentify === false) {
      setToIdentify([]);
    }
    if (showUpdates === false) {
      setUpdates([]);
    }
    updateModpackDetails();
  }, [showIdentify, showUpdates]);

  return (
    <div className="w-auto p-4 rounded-2xl flex flex-1 flex-col">
      <ModpackViewContext.Provider
        value={{
          removeMod: async (id: string) => {
            let newToIdentify = [...toIdentify];
            newToIdentify = newToIdentify.filter(
              (mod) =>
                mod.proposedMods.filter((mod) => mod.id === id).length === 0
            );
            setToIdentify(newToIdentify);
            if (newToIdentify.length === 0) {
              setShowIdentify(false);
            }
          },
        }}
      >
        <div className="bg-slate-700 p-4 flex align-middle rounded-2xl mt-2 mb-5 w-full font-bold items-center justify-center ">
          <p className="text-center ">
            {modpack.name} | {modpack.modLoader} | {modpack.version} |{" "}
            {t("modCount", { amount: modCount })}{" "}
            {modpack.lastSynced > 0 && (
              <>
                |{" "}
                {t("localSyncDate", {
                  date: new Intl.DateTimeFormat(quadrantLocale.language, {
                    weekday: "short",
                    day: "2-digit",
                    month: "2-digit",
                    year: "2-digit",
                    hour: "2-digit",
                    minute: "2-digit",
                    hour12: false,
                  }).format(new Date(modpack.lastSynced)),
                })}
              </>
            )}
          </p>
          <Button
            onClick={async () => {
              if (showUpdates) {
                setShowUpdates(false);
                return;
              }
              setShowUpdates(true);
              await checkForUpdates();
            }}
            className="bg-indigo-600 hover:bg-indigo-800 text-white ml-4 w-fit flex items-center "
          >
            {t("update")}
            <MdUpdate className="w-6 ml-2 h-6"></MdUpdate>
          </Button>
          {modpack.unknownMods && (
            <Button
              onClick={async () => {
                if (showIdentify) {
                  setShowIdentify(false);
                  return;
                }
                setShowIdentify(true);
                await getIdentifiedMods();
              }}
              className="bg-slate-600 hover:bg-slate-800 text-white mx-2 w-fit flex items-center "
            >
              {t("identifyUnknownMods")}
              <MdPermIdentity className="w-6 ml-2 h-6"></MdPermIdentity>
            </Button>
          )}
        </div>

        {showIdentify ? (
          toIdentify.length == 0 ? (
            <div className="bg-slate-800 w-full center h-min p-4 rounded-2xl">
              <CircularProgress></CircularProgress>
            </div>
          ) : (
            <>
              {toIdentify.map((mod, index) => {
                return (
                  <>
                    <div
                      key={mod.fileName + index}
                      className="bg-slate-800 rounded-2xl p-4 my-2"
                    >
                      <h1 className="font-bold">{mod.fileName} -&gt;</h1>
                      <div className="flex flex-row w-full mt-8">
                        {mod.proposedMods.map((mod, index) => {
                          return (
                            <Mod
                              key={mod.id + index}
                              className="w-max mx-2"
                              mod={mod}
                              modpack={modpack.name}
                            ></Mod>
                          );
                        })}
                      </div>
                    </div>
                  </>
                );
              })}
            </>
          )
        ) : !showUpdates ? (
          mods.length == 0 ? (
            <div className="bg-slate-800 w-full center h-min p-4 rounded-2xl">
              <CircularProgress></CircularProgress>
            </div>
          ) : (
            <div className="bg-slate-800 p-4 rounded-2xl mr-4 ml-2 mb-12 grid grid-cols-3 2xl:grid-cols-4 gap-6">
              {mods.map((mod, index) => {
                return (
                  <Mod
                    key={index}
                    className=" "
                    mod={mod}
                    modpack={modpack.name}
                  ></Mod>
                );
              })}
            </div>
          )
        ) : updates.length == 0 ? (
          <div className="bg-slate-800 w-full center h-min p-4 rounded-2xl">
            <CircularProgress></CircularProgress>
          </div>
        ) : (
          <div className="bg-slate-800 p-4 rounded-2xl mr-4 ml-2 mb-12 grid grid-cols-3 2xl:grid-cols-4 gap-6">
            {updates.map((mod, index) => {
              return (
                <Mod
                  key={index}
                  className=" "
                  mod={mod}
                  modpack={modpack.name}
                ></Mod>
              );
            })}
          </div>
        )}
      </ModpackViewContext.Provider>
    </div>
  );
}
