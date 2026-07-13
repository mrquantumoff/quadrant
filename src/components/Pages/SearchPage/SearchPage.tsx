/** @format */

import { useEffect, useMemo, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  IMod,
  LocalModpack,
  MinecraftVersion,
  ModSource,
  ModType,
  SearchCategory,
} from "../../../intefaces";
import {
  getCategories,
  getModpacks,
  getVersions,
  searchMods,
} from "../../../tools";
import Mod from "../../shared/Mod";
import "./SearchPage.css";
import {
  MdCheck,
  MdClose,
  MdExpandMore,
  MdExtension,
  MdFilterAlt,
  MdGridView,
  MdSearch,
  MdWbSunny,
} from "react-icons/md";
import CircularProgress from "../../core/CircularProgress";
import { AnimatePresence, motion } from "motion/react";
import { createDesktopStore } from "../../../desktop";
import {
  getModLoaderOptions,
  loaderProvidersFromSettings,
  loaderSupportsProvider,
} from "../../../modLoaders";

/** A category/facet unified across providers so a single row can carry both a
 *  CurseForge numeric id and a Modrinth slug. */
interface MergedCategory {
  key: string;
  name: string;
  header: string;
  cfId?: string;
  mrId?: string;
}

const CONTENT_TYPES: { type: ModType; labelKey: string; Icon: typeof MdSearch }[] =
  [
    { type: ModType.Mod, labelKey: "contentMods", Icon: MdExtension },
    { type: ModType.ResourcePack, labelKey: "contentResourcePacks", Icon: MdGridView },
    { type: ModType.ShaderPack, labelKey: "contentShaders", Icon: MdWbSunny },
  ];

const SORT_OPTIONS: { value: string; labelKey: string }[] = [
  { value: "relevance", labelKey: "sortRelevance" },
  { value: "downloads", labelKey: "sortDownloads" },
  { value: "name", labelKey: "sortName" },
  { value: "updated", labelKey: "sortUpdated" },
];

const HEADER_ORDER = ["categories", "resolutions", "features", "performance impact"];
const PILL_HEADERS = new Set(["resolutions", "performance impact"]);

// Known CurseForge↔Modrinth category-name equivalences, keyed by the normalized
// (lowercased, punctuation-stripped) name. CurseForge uses long editorial names
// while Modrinth uses short slugs, so without these aliases the two providers'
// facets never collapse into one "both" row and picking any category would
// source-lock the search to a single provider.
const CATEGORY_ALIASES: Record<string, string> = {
  worldgeneration: "worldgen",
  adventureandrpg: "adventure",
  apiandlibrary: "library",
  libraryandapi: "library",
  armortoolsandweapons: "equipment",
  playertransport: "transportation",
  utilityqol: "utility",
  utilityandqol: "utility",
};

/** Canonical merge token for a category name: lowercased, punctuation-stripped,
 *  then mapped through {@link CATEGORY_ALIASES}. */
function canonicalName(name: string): string {
  const compact = name
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, "");
  return CATEGORY_ALIASES[compact] ?? compact;
}

function mergeCategories(
  cf: SearchCategory[],
  mr: SearchCategory[],
): MergedCategory[] {
  const map = new Map<string, MergedCategory>();
  const add = (category: SearchCategory, which: "cf" | "mr") => {
    const key = `${category.header}:${canonicalName(category.name)}`;
    let merged = map.get(key);
    if (!merged) {
      merged = { key, name: category.name, header: category.header };
      map.set(key, merged);
    }
    if (which === "cf") {
      merged.cfId = category.id;
    } else {
      merged.mrId = category.id;
    }
  };
  // Modrinth first so its shorter, cleaner label wins for merged rows; Map
  // preserves insertion order, so no separate ordering array is needed.
  mr.forEach((category) => add(category, "mr"));
  cf.forEach((category) => add(category, "cf"));
  return [...map.values()];
}

export default function SearchPage() {
  const { t, i18n } = useTranslation();

  // Query + results. `rawLists` holds each provider's returned order so the
  // displayed results can be merged consistently after each provider search.
  const [searchQuery, setSearchQuery] = useState("");
  const [rawLists, setRawLists] = useState<IMod[][]>([]);
  const [searching, setSearching] = useState(false);
  const [searchError, setSearchError] = useState<string | null>(null);

  // Content type + sort
  const [contentType, setContentType] = useState<ModType>(ModType.Mod);
  const [sortBy, setSortBy] = useState("relevance");

  // Sources
  const [curseforge, setCurseforge] = useState(true);
  const [modrinth, setModrinth] = useState(true);

  // Filters
  const [version, setVersion] = useState("any");
  const [loader, setLoader] = useState<string>("");
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [openSource, setOpenSource] = useState(false);
  const [matchModpack, setMatchModpack] = useState(false);
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set());

  // Data
  const [versions, setVersions] = useState<MinecraftVersion[]>([]);
  const [modpacks, setModpacks] = useState<LocalModpack[]>([]);
  const [categories, setCategories] = useState<MergedCategory[]>([]);

  const searchRequestRef = useRef(0);
  const configRef = useRef(createDesktopStore("config.json"));
  const configStore = configRef.current;

  const catByKey = useMemo(() => {
    const map = new Map<string, MergedCategory>();
    categories.forEach((category) => map.set(category.key, category));
    return map;
  }, [categories]);

  const loaderVisible = contentType === ModType.Mod;

  // A single-provider category selection locks the source set to that provider.
  const lock = useMemo<"cf" | "modrinth" | null>(() => {
    for (const key of selected) {
      const merged = catByKey.get(key);
      if (!merged) continue;
      if (merged.cfId && !merged.mrId) return "cf";
      if (merged.mrId && !merged.cfId) return "modrinth";
    }
    return null;
  }, [selected, catByKey]);

  const effCf = curseforge && lock !== "modrinth" && !openSource;
  const effMr = modrinth && lock !== "cf";

  const currentModpack = useMemo(
    () => modpacks.find((modpack) => modpack.isApplied) ?? modpacks[0],
    [modpacks],
  );

  const loaderProviders = loaderProvidersFromSettings(effCf, effMr);
  const loaderOptions = useMemo(
    () => getModLoaderOptions(loaderProviders),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [effCf, effMr],
  );

  // Providers return bounded result sets in the requested order. Merge those
  // refreshed lists client-side to produce one ordering across providers.
  const mods = useMemo(
    () => orderResults(rawLists, sortBy),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [rawLists, sortBy, i18n.language],
  );

  const catIdsFor = (source: ModSource): string[] => {
    const ids: string[] = [];
    for (const key of selected) {
      const merged = catByKey.get(key);
      if (!merged) continue;
      const id = source === ModSource.CurseForge ? merged.cfId : merged.mrId;
      if (id) ids.push(id);
    }
    return ids;
  };

  const runSearch = async () => {
    const requestId = ++searchRequestRef.current;
    setSearching(true);
    setSearchError(null);

    try {
      const query = searchQuery.trim().toLowerCase();
      const base = {
        query,
        modType: contentType.toString(),
        // Only auto-installable when there is a concrete install target: a
        // matched modpack AND a concrete version (autoinstall reads the version
        // from config, so "Any version" has no unambiguous file to install).
        filterOn: matchModpack && version !== "any",
        gameVersion: version === "any" ? "" : version,
        modLoader: loaderVisible ? loader : "",
        openSource,
        sortBy,
      };

      const requests: Promise<IMod[]>[] = [];
      if (
        effCf &&
        (!base.modLoader || loaderSupportsProvider(base.modLoader, ModSource.CurseForge))
      ) {
        requests.push(
          searchMods({
            ...base,
            source: ModSource.CurseForge,
            categories: catIdsFor(ModSource.CurseForge),
          }),
        );
      }
      if (
        effMr &&
        (!base.modLoader || loaderSupportsProvider(base.modLoader, ModSource.Modrinth))
      ) {
        requests.push(
          searchMods({
            ...base,
            source: ModSource.Modrinth,
            categories: catIdsFor(ModSource.Modrinth),
          }),
        );
      }

      const settled = await Promise.allSettled(requests);
      if (requestId !== searchRequestRef.current) return;

      const failures = settled.filter((result) => result.status === "rejected");
      if (failures.length > 0 && failures.length === settled.length) {
        throw failures[0].reason;
      }
      failures.forEach((failure) =>
        console.error("Search provider failed", failure),
      );

      const lists = settled
        .filter(
          (result): result is PromiseFulfilledResult<IMod[]> =>
            result.status === "fulfilled",
        )
        .map((result) => result.value);
      setRawLists(lists);
    } catch (error) {
      if (requestId === searchRequestRef.current) {
        setSearchError(String(error));
        setRawLists([]);
      }
    } finally {
      if (requestId === searchRequestRef.current) {
        setSearching(false);
      }
    }
  };

  // Initial load: config, versions, modpacks.
  useEffect(() => {
    const boot = async () => {
      const [availableVersions, availableModpacks, cfEnabled, mrEnabled] =
        await Promise.all([
          getVersions(),
          getModpacks(),
          configStore.get<boolean>("curseforge"),
          configStore.get<boolean>("modrinth"),
        ]);
      setVersions(availableVersions);
      setModpacks(availableModpacks);
      setCurseforge(cfEnabled ?? true);
      setModrinth(mrEnabled ?? true);
    };
    boot().catch(console.error);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Fetch the facet taxonomy for the enabled sources whenever the content type
  // or source set changes. Skipping a disabled provider avoids a wasted request
  // and keeps its (unusable) facets out of the sidebar.
  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      const empty = Promise.resolve<SearchCategory[]>([]);
      const [cf, mr] = await Promise.all([
        curseforge
          ? getCategories(ModSource.CurseForge, contentType).catch(() => [])
          : empty,
        modrinth
          ? getCategories(ModSource.Modrinth, contentType).catch(() => [])
          : empty,
      ]);
      if (!cancelled) setCategories(mergeCategories(cf, mr));
    };
    load().catch(console.error);
    return () => {
      cancelled = true;
    };
  }, [contentType, curseforge, modrinth]);

  // Re-run the search whenever any query input changes. Taxonomy changes matter
  // because they can add a newly enabled provider's id to a selected category.
  useEffect(() => {
    void runSearch();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    contentType,
    curseforge,
    modrinth,
    version,
    loader,
    openSource,
    matchModpack,
    selected,
    categories,
    sortBy,
  ]);

  const toggleSource = (which: "cf" | "modrinth") => {
    if (which === "cf") setCurseforge((value) => !value);
    else setModrinth((value) => !value);
  };

  const selectType = (type: ModType) => {
    setContentType(type);
    setSelected(new Set());
    void changeLoader("");
  };

  const toggleCategory = (key: string) => {
    setSelected((previous) => {
      const next = new Set(previous);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  };

  // The version/loader the user picks drive both the search filter AND the
  // auto-install target (Mod.tsx reads lastUsedVersion/lastUsedAPI from config),
  // so persist every change to keep the two in lockstep.
  const changeVersion = async (value: string) => {
    if (matchModpack && value !== currentModpack?.version) {
      setMatchModpack(false);
    }
    setVersion(value);
    await configStore.set("lastUsedVersion", value === "any" ? "" : value);
    await configStore.save();
  };

  const changeLoader = async (value: string) => {
    if (matchModpack && value !== currentModpack?.modLoader) {
      setMatchModpack(false);
    }
    setLoader(value);
    await configStore.set("lastUsedAPI", value);
    await configStore.save();
  };

  const applyMatchModpack = async (enabled: boolean) => {
    // With no modpack to match, enabling would mark results auto-installable
    // into a nonexistent target, so it is a no-op.
    if (enabled && !currentModpack) return;
    setMatchModpack(enabled);
    if (enabled && currentModpack) {
      setVersion(currentModpack.version);
      setLoader(currentModpack.modLoader);
      await configStore.set("lastUsedModpack", currentModpack.name);
      await configStore.set("lastUsedVersion", currentModpack.version);
      await configStore.set("lastUsedAPI", currentModpack.modLoader);
      await configStore.save();
    }
  };

  const toggleOpenSource = () => {
    if (!openSource) {
      setSelected((previous) => {
        const next = new Set<string>();
        let changed = false;
        for (const key of previous) {
          const merged = catByKey.get(key);
          if (merged && merged.cfId && !merged.mrId) {
            changed = true;
            continue;
          }
          next.add(key);
        }
        return changed ? next : previous;
      });
    }
    setOpenSource((value) => !value);
  };

  const clearAll = () => {
    setSelected(new Set());
    void changeLoader("");
    setOpenSource(false);
    setMatchModpack(false);
  };

  const isDisabled = (category: MergedCategory): boolean => {
    // A single-provider facet is unusable when its only provider is turned off,
    // so don't let selecting it drive the effective source set to zero.
    if (!curseforge && category.cfId && !category.mrId) return true;
    if (!modrinth && category.mrId && !category.cfId) return true;
    if (lock === "cf" && category.mrId && !category.cfId) return true;
    if (lock === "modrinth" && category.cfId && !category.mrId) return true;
    if (openSource && category.cfId && !category.mrId) return true;
    return false;
  };

  // Active filter chips (categories + loader + toggles).
  const chips = useMemo(() => {
    const list: { key: string; label: string; onRemove: () => void }[] = [];
    for (const key of selected) {
      const merged = catByKey.get(key);
      if (merged) {
        list.push({
          key,
          label: merged.name,
          onRemove: () => toggleCategory(key),
        });
      }
    }
    if (loaderVisible && loader) {
      list.push({
        key: "loader",
        label: loader,
        onRemove: () => void changeLoader(""),
      });
    }
    if (openSource) {
      list.push({
        key: "os",
        label: t("openSourceOnly"),
        onRemove: () => setOpenSource(false),
      });
    }
    if (matchModpack) {
      list.push({
        key: "mp",
        label: t("matchCurrentModpack"),
        onRemove: () => setMatchModpack(false),
      });
    }
    return list;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selected, catByKey, loader, loaderVisible, openSource, matchModpack, t]);

  const sections = useMemo(() => {
    const byHeader = new Map<string, MergedCategory[]>();
    for (const category of categories) {
      const arr = byHeader.get(category.header) ?? [];
      arr.push(category);
      byHeader.set(category.header, arr);
    }
    const headers = [...byHeader.keys()].sort((a, b) => {
      const ai = HEADER_ORDER.indexOf(a);
      const bi = HEADER_ORDER.indexOf(b);
      return (ai === -1 ? 99 : ai) - (bi === -1 ? 99 : bi);
    });
    return headers.map((header) => ({
      header,
      title: headerTitle(header, t),
      pill: PILL_HEADERS.has(header),
      options: byHeader.get(header)!,
    }));
  }, [categories, t]);

  const contentLabel = t(
    CONTENT_TYPES.find((entry) => entry.type === contentType)?.labelKey ??
      "contentMods",
  ).toLowerCase();

  return (
    <motion.div
      initial={{ y: 24, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      exit={{ y: 24, opacity: 0 }}
      className="content-main flex flex-col w-full h-full min-h-0 text-slate-50 transform-gpu [backface-visibility:hidden] [will-change:transform,opacity]"
    >
      {/* Search + submit */}
      <div className="flex-none flex justify-center px-6 pt-5 pb-4">
        <form
          onSubmit={async (event) => {
            event.preventDefault();
            await runSearch();
          }}
          className="flex gap-2.5 items-center w-full"
        >
          <div className="flex-1 relative flex items-center">
            <MdSearch className="absolute left-3.5 w-4 h-4 text-slate-500 pointer-events-none" />
            <input
              value={searchQuery}
              onChange={(event) => setSearchQuery(event.target.value)}
              autoComplete="off"
              placeholder={t("searchPlaceholder", { type: contentLabel })}
              className="w-full h-10 pl-10 pr-4 rounded-full border-none bg-slate-800 text-slate-50 text-sm font-medium outline-none focus:shadow-[0_0_0_2px_var(--color-blue-600)]"
            />
          </div>
          <button
            type="submit"
            className="inline-flex items-center gap-2 h-10 px-5 rounded-full bg-sky-700 hover:bg-sky-600 text-white text-sm font-extrabold whitespace-nowrap"
          >
            <MdSearch className="w-[18px] h-[18px]" />
            {t("search")}
          </button>
        </form>
      </div>

      {/* Body */}
      <div className="flex-1 flex min-h-0 gap-4 px-6 pb-6">
        {/* Filters sidebar */}
        <aside className="flex-none w-[316px] flex flex-col min-h-0">
          <div className="bg-slate-800 rounded-[28px] flex flex-col min-h-0 h-full overflow-hidden">
            <div className="flex-none flex items-center justify-between px-6 pt-5 pb-3">
              <div className="flex items-center gap-2">
                <MdFilterAlt className="w-[18px] h-[18px] text-slate-200" />
                <span className="text-[17px] font-extrabold tracking-tight">
                  {t("filter")}
                </span>
                {chips.length > 0 && (
                  <span className="min-w-[22px] h-[22px] px-[7px] rounded-full bg-blue-600 text-white text-xs font-extrabold inline-flex items-center justify-center">
                    {chips.length}
                  </span>
                )}
              </div>
              {chips.length > 0 && (
                <button
                  onClick={clearAll}
                  className="text-slate-400 text-xs font-bold hover:text-red-400"
                >
                  {t("clearAll")}
                </button>
              )}
            </div>

            <div className="flex-1 min-h-0 overflow-y-auto px-6 pb-6">
              {/* Source */}
              <div className="mb-6">
                <div className="text-[13px] font-extrabold text-slate-400 mb-2.5">
                  {t("source")}
                </div>
                <div className="flex gap-2">
                  <SourceToggle
                    label="CurseForge"
                    dot="#f16436"
                    active={effCf}
                    disabled={lock === "modrinth" || openSource}
                    onToggle={() => toggleSource("cf")}
                  />
                  <SourceToggle
                    label="Modrinth"
                    dot="#1bd96a"
                    active={effMr}
                    disabled={lock === "cf"}
                    onToggle={() => toggleSource("modrinth")}
                  />
                </div>
                {lock && (
                  <div className="mt-2.5 text-[11.5px] leading-snug text-amber-300 bg-amber-900/25 border border-amber-700/20 px-3 py-2 rounded-2xl">
                    {t("sourceLockHint", {
                      source: lock === "cf" ? "CurseForge" : "Modrinth",
                    })}
                  </div>
                )}
              </div>

              {/* Content type */}
              <div className="mb-6">
                <div className="text-[13px] font-extrabold text-slate-400 mb-2.5">
                  {t("contentType")}
                </div>
                <div className="flex flex-wrap gap-1.5">
                  {CONTENT_TYPES.map(({ type, labelKey, Icon }) => {
                    const active = contentType === type;
                    return (
                      <button
                        key={type}
                        onClick={() => selectType(type)}
                        className={
                          "inline-flex items-center gap-1.5 h-8 px-3 rounded-full text-[13px] font-bold transition-[filter] hover:brightness-110 " +
                          (active
                            ? "bg-blue-600 text-white"
                            : "bg-slate-700 text-slate-200")
                        }
                      >
                        <Icon className="w-4 h-4" />
                        {t(labelKey)}
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* Quick filter: match current modpack */}
              <div className="mb-6">
                <button
                  onClick={() => void applyMatchModpack(!matchModpack)}
                  disabled={!currentModpack}
                  className={
                    "w-full flex items-center justify-center gap-2 h-10 px-4 rounded-full text-[13.5px] font-extrabold transition-[filter] " +
                    (!currentModpack
                      ? "bg-slate-800 text-slate-600 cursor-not-allowed"
                      : matchModpack
                        ? "bg-blue-600 text-white hover:brightness-110"
                        : "bg-slate-700 text-slate-200 hover:brightness-110")
                  }
                >
                  {matchModpack && <MdCheck className="w-4 h-4" />}
                  {t("matchCurrentModpack")}
                </button>
                {currentModpack && (
                  <div className="mt-1.5 text-[11.5px] text-slate-500 font-medium truncate text-center">
                    {currentModpack.name} · {currentModpack.modLoader} ·{" "}
                    {currentModpack.version}
                  </div>
                )}
              </div>

              {/* Minecraft version */}
              <div className="mb-6">
                <div className="text-[13px] font-extrabold text-slate-400 mb-2.5">
                  {t("minecraftVersion")}
                </div>
                <select
                  value={version}
                  onChange={(event) => void changeVersion(event.target.value)}
                  className="w-full h-11 px-4 rounded-full border-none bg-slate-700 text-slate-200 text-sm font-bold cursor-pointer outline-none hover:brightness-110"
                >
                  <option value="any">{t("anyVersion")}</option>
                  {versions.map((entry) => (
                    <option key={entry.version} value={entry.version}>
                      {entry.version}
                    </option>
                  ))}
                </select>
              </div>

              {/* Loader */}
              {loaderVisible && (
                <div className="mb-6">
                  <div className="text-[13px] font-extrabold text-slate-400 mb-2.5">
                    {t("loader")}
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    {loaderOptions.map((option) => {
                      const active = loader === option.value;
                      return (
                        <button
                          key={option.value}
                          onClick={() =>
                            void changeLoader(active ? "" : (option.value as string))
                          }
                          className={
                            "inline-flex items-center h-8 px-3.5 rounded-full text-[13px] font-bold transition-[filter] hover:brightness-110 " +
                            (active
                              ? "bg-blue-600 text-white"
                              : "bg-slate-700 text-slate-200")
                          }
                        >
                          {option.label}
                        </button>
                      );
                    })}
                  </div>
                </div>
              )}

              {/* Dynamic facet sections */}
              {sections.map((section) => {
                const isCollapsed = collapsed.has(section.header);
                return (
                  <div
                    key={section.header}
                    className="border-t border-white/10 pt-4 mb-3.5"
                  >
                    <button
                      onClick={() =>
                        setCollapsed((previous) => {
                          const next = new Set(previous);
                          if (next.has(section.header)) next.delete(section.header);
                          else next.add(section.header);
                          return next;
                        })
                      }
                      className="w-full flex items-center justify-between pb-3 text-slate-50"
                    >
                      <span className="text-[15px] font-extrabold tracking-tight">
                        {section.title}
                      </span>
                      <MdExpandMore
                        className={
                          "w-[17px] h-[17px] text-slate-400 transition-transform " +
                          (isCollapsed ? "rotate-180" : "")
                        }
                      />
                    </button>
                    {!isCollapsed &&
                      (section.pill ? (
                        <div className="flex flex-wrap gap-1.5">
                          {section.options.map((option) => (
                            <PillOption
                              key={option.key}
                              category={option}
                              selected={selected.has(option.key)}
                              disabled={isDisabled(option)}
                              onToggle={() => toggleCategory(option.key)}
                            />
                          ))}
                        </div>
                      ) : (
                        <div className="flex flex-col gap-px">
                          {section.options.map((option) => (
                            <CheckOption
                              key={option.key}
                              category={option}
                              selected={selected.has(option.key)}
                              disabled={isDisabled(option)}
                              onToggle={() => toggleCategory(option.key)}
                            />
                          ))}
                        </div>
                      ))}
                  </div>
                );
              })}

              {/* Global toggles */}
              <div className="border-t border-white/10 pt-4 flex flex-col gap-4">
                <SwitchRow
                  label={t("openSourceOnly")}
                  on={openSource}
                  onToggle={toggleOpenSource}
                />
              </div>
            </div>
          </div>
        </aside>

        {/* Results */}
        <main className="flex-1 min-w-0 flex flex-col min-h-0">
          <div className="flex-none flex items-center gap-3 flex-wrap mb-3">
            <span className="text-sm text-slate-400 font-bold">
              {t("resultCount", { count: mods.length, type: contentLabel })}
            </span>
            <div className="flex-1" />
            <div className="flex items-center gap-2">
              <span className="text-xs text-slate-500 font-bold">
                {t("sortBy")}
              </span>
              <select
                value={sortBy}
                onChange={(event) => setSortBy(event.target.value)}
                className="h-9 px-4 rounded-full border-none bg-slate-800 text-slate-200 text-[13.5px] font-bold cursor-pointer outline-none hover:brightness-110"
              >
                {SORT_OPTIONS.map((option) => (
                  <option key={option.value} value={option.value}>
                    {t(option.labelKey)}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {chips.length > 0 && (
            <div className="flex-none flex flex-wrap gap-2 mb-3.5">
              {chips.map((chip) => (
                <button
                  key={chip.key}
                  onClick={chip.onRemove}
                  className="inline-flex items-center gap-1.5 h-8 pl-3.5 pr-2 rounded-full bg-slate-700 text-slate-200 text-[12.5px] font-bold hover:bg-red-900 hover:text-red-200"
                >
                  {chip.label}
                  <MdClose className="w-3.5 h-3.5" />
                </button>
              ))}
            </div>
          )}

          <div className="flex-1 min-h-0 overflow-y-auto bg-slate-800 rounded-[28px] p-[18px]">
            {searchError ? (
              <div className="bg-red-700 rounded-4xl p-4 font-bold">
                {searchError}
              </div>
            ) : !effCf && !effMr ? (
              <div className="flex flex-col items-center justify-center py-[70px] px-5 text-center text-slate-500">
                <MdFilterAlt className="w-12 h-12 text-slate-700" />
                <div className="text-[17px] font-extrabold text-slate-400 mt-4">
                  {t("noActiveSourceTitle")}
                </div>
                <div className="text-[13.5px] mt-1.5 max-w-[360px] leading-relaxed">
                  {t("noActiveSourceHint")}
                </div>
                {chips.length > 0 && (
                  <button
                    onClick={clearAll}
                    className="mt-4 h-10 px-5 rounded-full bg-slate-700 hover:bg-slate-600 text-slate-50 text-[13.5px] font-extrabold"
                  >
                    {t("clearAllFilters")}
                  </button>
                )}
              </div>
            ) : searching ? (
              <div className="flex items-center justify-center py-16">
                <CircularProgress />
              </div>
            ) : mods.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-[70px] px-5 text-center text-slate-500">
                <MdSearch className="w-12 h-12 text-slate-700" />
                <div className="text-[17px] font-extrabold text-slate-400 mt-4">
                  {t("noResultsTitle")}
                </div>
                <div className="text-[13.5px] mt-1.5 max-w-[360px] leading-relaxed">
                  {t("noResultsHint")}
                </div>
                {chips.length > 0 && (
                  <button
                    onClick={clearAll}
                    className="mt-4 h-10 px-5 rounded-full bg-slate-700 hover:bg-slate-600 text-slate-50 text-[13.5px] font-extrabold"
                  >
                    {t("clearAllFilters")}
                  </button>
                )}
              </div>
            ) : (
              <div className="grid gap-3 [grid-template-columns:repeat(auto-fill,minmax(300px,1fr))]">
                <AnimatePresence>
                  {mods.map((mod, index) => (
                    <Mod
                      key={`${mod.source}-${mod.id}-${index}`}
                      className=""
                      mod={mod}
                      modpack={undefined}
                    />
                  ))}
                </AnimatePresence>
              </div>
            )}
          </div>
        </main>
      </div>
    </motion.div>
  );

  function orderResults(lists: IMod[][], key: string): IMod[] {
    // Relevance: each provider already returns its own ranked list, so preserve
    // those rankings by round-robin interleaving rather than re-sorting.
    if (key === "relevance") {
      const out: IMod[] = [];
      const longest = lists.reduce((max, list) => Math.max(max, list.length), 0);
      for (let i = 0; i < longest; i++) {
        for (const list of lists) {
          if (i < list.length) out.push(list[i]);
        }
      }
      return out;
    }

    const flat = lists.flat();
    if (key === "name") {
      return flat.sort((a, b) => a.name.localeCompare(b.name, i18n.language));
    }
    if (key === "updated") {
      return flat.sort(
        (a, b) => dateValue(b.dateModified) - dateValue(a.dateModified),
      );
    }
    // downloads (default)
    return flat.sort((a, b) => b.downloadCount - a.downloadCount);
  }
}

/** Parses an RFC 3339 timestamp to millis; unknown/blank sorts oldest. */
function dateValue(value: string): number {
  if (!value) return 0;
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? 0 : parsed;
}

function headerTitle(
  header: string,
  t: (key: string) => string,
): string {
  switch (header) {
    case "categories":
      return t("categories");
    case "resolutions":
      return t("resolution");
    case "features":
      return t("features");
    case "performance impact":
      return t("performanceImpact");
    default:
      return header.replace(/\b\w/g, (char) => char.toUpperCase());
  }
}

function SourceBadge({ category }: { category: MergedCategory }) {
  if (category.cfId && category.mrId) return null;
  const isCf = !!category.cfId;
  return (
    <span
      className={
        "flex-none text-[9.5px] font-extrabold tracking-wide px-1.5 py-0.5 rounded-md " +
        (isCf
          ? "bg-orange-500/20 text-orange-400"
          : "bg-emerald-500/15 text-emerald-400")
      }
    >
      {isCf ? "CF" : "MR"}
    </span>
  );
}

function CheckOption({
  category,
  selected,
  disabled,
  onToggle,
}: {
  category: MergedCategory;
  selected: boolean;
  disabled: boolean;
  onToggle: () => void;
}) {
  return (
    <button
      onClick={disabled ? undefined : onToggle}
      disabled={disabled}
      className={
        "flex items-center gap-2.5 w-full px-2 py-1.5 rounded-xl text-left " +
        (disabled ? "opacity-55 cursor-not-allowed" : "cursor-pointer hover:bg-white/5")
      }
    >
      <span
        className={
          "flex-none w-5 h-5 rounded-[7px] flex items-center justify-center border " +
          (disabled
            ? "border-slate-700"
            : selected
              ? "border-blue-600 bg-blue-600"
              : "border-slate-500")
        }
      >
        {selected && !disabled && <MdCheck className="w-3 h-3 text-white" />}
      </span>
      <span
        className={
          "flex-1 text-[13.5px] font-medium " +
          (disabled ? "text-slate-600" : selected ? "text-slate-50" : "text-slate-300")
        }
      >
        {category.name}
      </span>
      <SourceBadge category={category} />
    </button>
  );
}

function PillOption({
  category,
  selected,
  disabled,
  onToggle,
}: {
  category: MergedCategory;
  selected: boolean;
  disabled: boolean;
  onToggle: () => void;
}) {
  return (
    <button
      onClick={disabled ? undefined : onToggle}
      disabled={disabled}
      className={
        "inline-flex items-center gap-1.5 h-[34px] px-3.5 rounded-full text-[13px] font-bold transition-[filter] " +
        (disabled
          ? "bg-slate-800 text-slate-600 cursor-not-allowed"
          : selected
            ? "bg-blue-600 text-white hover:brightness-110"
            : "bg-slate-700 text-slate-200 hover:brightness-110")
      }
    >
      {category.name}
    </button>
  );
}

function SourceToggle({
  label,
  dot,
  active,
  disabled,
  onToggle,
}: {
  label: string;
  dot: string;
  active: boolean;
  disabled: boolean;
  onToggle: () => void;
}) {
  return (
    <button
      onClick={disabled ? undefined : onToggle}
      disabled={disabled}
      className={
        "flex-1 inline-flex items-center justify-center gap-2 h-[42px] rounded-full text-[13.5px] font-extrabold transition-[filter] " +
        (disabled
          ? "bg-slate-800 border border-dashed border-slate-700 text-slate-600 cursor-not-allowed"
          : active
            ? "bg-slate-700 border-2 border-blue-600 text-slate-50 hover:brightness-110"
            : "bg-slate-800 border-2 border-transparent text-slate-500 hover:brightness-110")
      }
    >
      <span
        className="w-2.5 h-2.5 rounded-full flex-none"
        style={{ background: dot }}
      />
      {label}
    </button>
  );
}

function SwitchRow({
  label,
  on,
  onToggle,
}: {
  label: string;
  on: boolean;
  onToggle: () => void;
}) {
  return (
    <button
      onClick={onToggle}
      className="flex items-center justify-between w-full cursor-pointer"
    >
      <span className="text-sm font-medium text-slate-300 text-left">
        {label}
      </span>
      <span
        className={
          "flex-none w-[42px] h-6 rounded-full relative transition-colors " +
          (on ? "bg-blue-600" : "bg-slate-700")
        }
      >
        <span
          className={
            "absolute top-0.5 left-0.5 w-5 h-5 rounded-full bg-white transition-transform " +
            (on ? "translate-x-[18px]" : "")
          }
        />
      </span>
    </button>
  );
}
