import quadrantLocale from "../../../i18n";
import { IMod, LocalModpack, ModSource, ModType } from "../../../intefaces";
import { useEffect, useState } from "react";
import { getMod, getModUpdate } from "../../../tools";
import Mod from "../Mod";
import { useTranslation } from "react-i18next";
import CircularProgress from "../../core/CircularProgress";

import Button from "../../core/Button";
import { MdUpdate } from "react-icons/md";

export default function ModpackView(modpack: LocalModpack) {
  const localMods = modpack.mods;
  const [mods, setMods] = useState<IMod[]>([]);
  const [updates, setUpdates] = useState<IMod[]>([]);
  const [showUpdates, setShowUpdates] = useState(false);
  const [modCount, setModCount] = useState(mods.length);

  const updateModpackDetails = async () => {
    setMods([]);
    if (!showUpdates) {
      setModCount(0);
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

  const { t } = useTranslation();
  useEffect(() => {
    const effect = async () => {
      await updateModpackDetails();
    };

    effect().catch((e) => console.error(e));
  }, []);

  return (
    <div className="w-auto p-4 rounded-2xl flex flex-1 flex-col">
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
              updateModpackDetails();
              return;
            }
            setShowUpdates(true);
            await checkForUpdates();
          }}
          className="bg-indigo-600 hover:bg-indigo-800 text-white mx-4 w-fit flex items-center "
        >
          {t("update")}
          <MdUpdate className="w-6 ml-2 h-6"></MdUpdate>
        </Button>
      </div>

      {!showUpdates ? (
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
    </div>
  );
}
