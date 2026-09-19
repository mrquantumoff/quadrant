/** @format */

import { useContext, useEffect, useRef, useState } from "react";
import {
  Disclosure,
  DisclosureButton,
  DisclosurePanel,
} from "@headlessui/react";
import { motion } from "motion/react";
import { useTranslation } from "react-i18next";
import type { TFunction } from "i18next";
import {
  MdCheck,
  MdDelete,
  MdExpandMore,
  MdFolder,
  MdRefresh,
} from "react-icons/md";
import {
  ContentContext,
  ContentFile,
  ContentLocation,
  ModType,
} from "../../../intefaces";
import {
  copyContent,
  deleteContent,
  getInstalledContent,
  openContentFolder,
} from "../../../tools";
import quadrantLocale from "../../../i18n";
import Button from "../../core/Button";
import CircularProgress from "../../core/CircularProgress";
import CopyToMenu from "./CopyToMenu";
import {
  ContentSelection,
  controlKey,
  copyTargets,
  filesOf,
  pruneSelection,
  selectedIn,
  selectionKey,
  toggleSelection,
} from "./contentActions";
import { useReportError } from "../../../useReportError";

const cardClass = "flex flex-col bg-slate-900 p-4 rounded-4xl mx-5 my-5 h-max";
const actionClass =
  "flex items-center justify-center h-10 shrink-0 text-sm bg-slate-700 hover:bg-slate-600 px-4 w-max";

/** How long an armed delete waits for its confirming click. */
const ARM_TIMEOUT_MS = 4000;

interface SizeUnit {
  /** An `Intl.NumberFormat` unit identifier. */
  unit: string;
  bytes: number;
}

const SIZE_UNITS: SizeUnit[] = [
  { unit: "byte", bytes: 1 },
  { unit: "kilobyte", bytes: 1024 },
  { unit: "megabyte", bytes: 1024 ** 2 },
  { unit: "gigabyte", bytes: 1024 ** 3 },
];

function formatSize(bytes: number): string {
  let chosen = SIZE_UNITS[0];
  for (const candidate of SIZE_UNITS) {
    if (bytes >= candidate.bytes) {
      chosen = candidate;
    }
  }
  return new Intl.NumberFormat(quadrantLocale.language, {
    style: "unit",
    unit: chosen.unit,
    unitDisplay: "narrow",
    maximumFractionDigits: 1,
  }).format(bytes / chosen.bytes);
}

function formatModified(modified: number): string {
  return new Intl.DateTimeFormat(quadrantLocale.language, {
    day: "2-digit",
    month: "2-digit",
    year: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(new Date(modified));
}

function describeFile(file: ContentFile, t: TFunction): string {
  const parts = [
    file.isDirectory ? t("installedContentFolderEntry") : formatSize(file.size),
  ];
  if (file.modified !== 0) {
    parts.push(formatModified(file.modified));
  }
  return parts.join(" · ");
}

function locationTitle(location: ContentLocation, t: TFunction): string {
  return location.kind === "minecraft"
    ? t("installedContentMinecraft")
    : location.name;
}

interface ContentSection {
  titleKey: string;
  modType: ModType;
  files: ContentFile[];
}

function sectionsOf(location: ContentLocation): ContentSection[] {
  return [
    {
      titleKey: "contentResourcePacks",
      modType: ModType.ResourcePack,
      files: filesOf(location, ModType.ResourcePack),
    },
    {
      titleKey: "contentShaders",
      modType: ModType.ShaderPack,
      files: filesOf(location, ModType.ShaderPack),
    },
  ];
}

interface CopyRequest {
  /** The control the copy was started from, per `controlKey`. */
  key: string;
  from: ContentLocation;
  to: ContentLocation;
  modType: ModType;
  fileNames: string[];
}

interface DeleteRequest {
  /** The control the delete was started from, per `controlKey`. */
  key: string;
  location: ContentLocation;
  modType: ModType;
  fileNames: string[];
}

interface ContentActions {
  locations: ContentLocation[];
  /** The running copy or delete's key, or null while nothing is running. */
  pending: string | null;
  /** The delete control waiting for its confirming click, or null. */
  armedKey: string | null;
  selection: ContentSelection | null;
  copy: (request: CopyRequest) => void;
  /** Arms the control, or runs the delete when it is already armed. */
  askDelete: (request: DeleteRequest) => void;
  disarm: () => void;
  select: (next: ContentSelection | null) => void;
}

interface DeleteButtonProps {
  request: DeleteRequest;
  actions: ContentActions;
  label: string;
  armedLabel: string;
  /** Shown while idle. The per-file control is icon-only and leaves it out. */
  text?: string;
  armedText: string;
}

function DeleteButton({
  request,
  actions,
  label,
  armedLabel,
  text,
  armedText,
}: DeleteButtonProps) {
  const armed = actions.armedKey === request.key;
  return (
    <Button
      onClick={() => actions.askDelete(request)}
      onBlur={() => {
        if (armed) {
          actions.disarm();
        }
      }}
      disabled={actions.pending !== null}
      aria-label={armed ? armedLabel : label}
      title={armed ? armedLabel : label}
      className={
        "flex items-center justify-center h-10 shrink-0 text-sm " +
        (armed
          ? "bg-red-700 hover:bg-red-600 px-4 w-max"
          : text === undefined
            ? "bg-slate-800 hover:bg-red-700 w-10"
            : "bg-slate-800 hover:bg-red-700 px-4 w-max")
      }
    >
      {armed ? armedText : text}
      <MdDelete
        aria-hidden="true"
        className={"w-5 h-5 " + (armed || text !== undefined ? "ml-2" : "")}
      />
    </Button>
  );
}

interface ContentFileRowProps {
  location: ContentLocation;
  modType: ModType;
  file: ContentFile;
  actions: ContentActions;
  selected: boolean;
}

function ContentFileRow({
  location,
  modType,
  file,
  actions,
  selected,
}: ContentFileRowProps) {
  const { t } = useTranslation();
  const rowKey = controlKey(location.id, modType, file.fileName);

  return (
    <li className="bg-slate-900 rounded-4xl px-4 py-2 my-1 flex items-center gap-3">
      <input
        type="checkbox"
        aria-label={file.fileName}
        checked={selected}
        disabled={actions.pending !== null}
        onChange={() =>
          actions.select(
            toggleSelection(
              actions.selection,
              location.id,
              modType,
              file.fileName,
            ),
          )
        }
        className="shrink-0 w-5 h-5 accent-emerald-600 hover:cursor-pointer disabled:cursor-default"
      />
      <div className="min-w-0 flex-1">
        <p className="font-bold break-words">{file.fileName}</p>
        <p className="text-md text-slate-400">{describeFile(file, t)}</p>
      </div>
      {actions.locations.length > 1 && (
        <CopyToMenu
          label={t("installedContentCopyFileLabel", { file: file.fileName })}
          busy={actions.pending === rowKey}
          disabled={actions.pending !== null}
          options={copyTargets(actions.locations, location.id, modType, [
            file.fileName,
          ]).map((target) => ({
            location: target.location,
            label: locationTitle(target.location, t),
            disabled: target.missing.length === 0,
          }))}
          onPick={(destination) =>
            actions.copy({
              key: rowKey,
              from: location,
              to: destination,
              modType,
              fileNames: [file.fileName],
            })
          }
        />
      )}
      <DeleteButton
        request={{ key: rowKey, location, modType, fileNames: [file.fileName] }}
        actions={actions}
        label={t("installedContentDeleteLabel", { file: file.fileName })}
        armedLabel={t("installedContentDeleteConfirmLabel", {
          file: file.fileName,
        })}
        armedText={t("installedContentDeleteConfirm")}
      />
    </li>
  );
}

interface SelectionBarProps {
  location: ContentLocation;
  section: ContentSection;
  actions: ContentActions;
  selected: string[];
}

function SelectionBar({
  location,
  section,
  actions,
  selected,
}: SelectionBarProps) {
  const { t } = useTranslation();
  const key = selectionKey(location.id, section.modType);
  const targets = copyTargets(
    actions.locations,
    location.id,
    section.modType,
    selected,
  );

  return (
    <div className="flex flex-wrap items-center gap-2 mt-3">
      <span className="font-extrabold text-sm mr-auto">
        {t("installedContentSelected", { count: selected.length })}
      </span>
      <Button
        onClick={() =>
          actions.select({
            locationId: location.id,
            modType: section.modType,
            fileNames: section.files.map((file) => file.fileName),
          })
        }
        disabled={actions.pending !== null}
        className={actionClass}
      >
        {t("installedContentSelectAll")}
      </Button>
      <Button
        onClick={() => actions.select(null)}
        disabled={actions.pending !== null}
        className={actionClass}
      >
        {t("installedContentClearSelection")}
      </Button>
      {actions.locations.length > 1 && (
        <CopyToMenu
          text={t("installedContentCopySelected")}
          label={t("installedContentCopySelectedLabel")}
          busy={actions.pending === key}
          disabled={actions.pending !== null}
          options={targets.map((target) => ({
            location: target.location,
            label: t("installedContentCopyMissing", {
              name: locationTitle(target.location, t),
              missing: target.missing.length,
            }),
            disabled: target.missing.length === 0,
          }))}
          onPick={(destination) =>
            actions.copy({
              key,
              from: location,
              to: destination,
              modType: section.modType,
              fileNames:
                targets.find((target) => target.location.id === destination.id)
                  ?.missing ?? [],
            })
          }
        />
      )}
      <DeleteButton
        request={{
          key,
          location,
          modType: section.modType,
          fileNames: selected,
        }}
        actions={actions}
        label={t("installedContentDeleteSelected")}
        text={t("installedContentDeleteSelected")}
        armedLabel={t("installedContentDeleteSelectedConfirm", {
          amount: selected.length,
        })}
        armedText={t("installedContentDeleteSelectedConfirm", {
          amount: selected.length,
        })}
      />
    </div>
  );
}

interface ContentSectionViewProps {
  location: ContentLocation;
  section: ContentSection;
  actions: ContentActions;
}

function ContentSectionView({
  location,
  section,
  actions,
}: ContentSectionViewProps) {
  const { t } = useTranslation();
  const reportError = useReportError();
  const sectionTitle = t(section.titleKey);
  const locationName = locationTitle(location, t);
  const selected = selectedIn(actions.selection, location.id, section.modType);
  const allNames = section.files.map((file) => file.fileName);
  const allKey = controlKey(location.id, section.modType);
  const allTargets = copyTargets(
    actions.locations,
    location.id,
    section.modType,
    allNames,
  );

  return (
    <Disclosure as="div" className="bg-slate-800 rounded-4xl p-4 my-3">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
        <DisclosureButton className="group flex min-w-0 flex-1 items-center gap-x-3 text-start hover:cursor-pointer">
          <span className="font-extrabold text-lg">{sectionTitle}</span>
          <span className="text-md text-slate-400">{section.files.length}</span>
          <MdExpandMore
            aria-hidden="true"
            className="h-5 w-5 shrink-0 group-data-open:rotate-180"
          />
        </DisclosureButton>
        {actions.locations.length > 1 && section.files.length > 0 && (
          <CopyToMenu
            text={t("installedContentCopyAll")}
            label={t("installedContentCopyAllLabel", {
              section: sectionTitle,
              name: locationName,
            })}
            busy={actions.pending === allKey}
            disabled={actions.pending !== null}
            options={allTargets.map((target) => ({
              location: target.location,
              label: t("installedContentCopyMissing", {
                name: locationTitle(target.location, t),
                missing: target.missing.length,
              }),
              disabled: target.missing.length === 0,
            }))}
            onPick={(destination) =>
              actions.copy({
                key: allKey,
                from: location,
                to: destination,
                modType: section.modType,
                fileNames:
                  allTargets.find(
                    (target) => target.location.id === destination.id,
                  )?.missing ?? [],
              })
            }
          />
        )}
        <Button
          onClick={async () => {
            try {
              await openContentFolder(location.id, section.modType);
            } catch (e: any) {
              reportError(e);
            }
          }}
          className="flex items-center self-center bg-slate-700 hover:bg-slate-600 px-4 w-max h-10 justify-center text-sm"
          aria-label={t("installedContentOpenFolderLabel", {
            section: sectionTitle,
            name: locationName,
          })}
        >
          {t("installedContentOpenFolder")}
          <MdFolder aria-hidden="true" className="w-5 h-5 mx-2" />
        </Button>
      </div>
      <DisclosurePanel>
        {selected.length > 0 && (
          <SelectionBar
            location={location}
            section={section}
            actions={actions}
            selected={selected}
          />
        )}
        {section.files.length === 0 ? (
          <p className="text-md text-slate-400 mt-3">
            {t("installedContentEmpty")}
          </p>
        ) : (
          <ul className="mt-3 flex flex-col">
            {section.files.map((file) => (
              <ContentFileRow
                key={file.fileName}
                location={location}
                modType={section.modType}
                file={file}
                actions={actions}
                selected={selected.includes(file.fileName)}
              />
            ))}
          </ul>
        )}
      </DisclosurePanel>
    </Disclosure>
  );
}

interface LocationCardProps {
  location: ContentLocation;
  /** The first location is always expanded; the rest fold away. */
  collapsible: boolean;
  actions: ContentActions;
}

function LocationCard({ location, collapsible, actions }: LocationCardProps) {
  const { t } = useTranslation();
  const title = locationTitle(location, t);
  const hasContent =
    location.resourcePacks.length + location.shaderPacks.length > 0;

  const header = (
    <div className="min-w-0 flex-1 text-start">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
        <span className="text-2xl font-extrabold break-words">{title}</span>
        {location.kind === "prism" && (
          <span className="bg-slate-700 rounded-full px-3 py-1 text-xs font-extrabold text-slate-300">
            {t("prismLauncher")}
          </span>
        )}
      </div>
      <span className="block text-md text-slate-400 break-all">
        {location.path}
      </span>
    </div>
  );

  const sections = sectionsOf(location).map((section) => (
    <ContentSectionView
      key={section.modType}
      location={location}
      section={section}
      actions={actions}
    />
  ));

  if (!collapsible) {
    return (
      <div className={cardClass}>
        {header}
        {sections}
      </div>
    );
  }

  return (
    <Disclosure as="div" className={cardClass} defaultOpen={hasContent}>
      <DisclosureButton className="group flex w-full items-center gap-3 hover:cursor-pointer">
        {header}
        <MdExpandMore
          aria-hidden="true"
          className="h-6 w-6 shrink-0 group-data-open:rotate-180"
        />
      </DisclosureButton>
      <DisclosurePanel>{sections}</DisclosurePanel>
    </Disclosure>
  );
}

export default function InstalledContentPage() {
  const { t } = useTranslation();
  const reportError = useReportError();
  const context = useContext(ContentContext);
  // `undefined` while the first load is in flight; a failed load settles on an
  // empty list so the page stays usable and the refresh button acts as the retry.
  const [locations, setLocations] = useState<ContentLocation[] | undefined>(
    undefined,
  );
  const [reloadToken, setReloadToken] = useState(0);
  const [pending, setPending] = useState<string | null>(null);
  const [armedKey, setArmedKey] = useState<string | null>(null);
  const [selection, setSelection] = useState<ContentSelection | null>(null);
  const armTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const disarm = () => {
    if (armTimer.current !== null) {
      clearTimeout(armTimer.current);
      armTimer.current = null;
    }
    setArmedKey(null);
  };

  useEffect(() => {
    let cancelled = false;
    setLocations(undefined);
    setSelection(null);
    const effect = async () => {
      try {
        const loaded = await getInstalledContent();
        if (!cancelled) {
          setLocations(loaded);
        }
      } catch (error) {
        if (cancelled) {
          return;
        }
        setLocations([]);
        reportError(error);
      }
    };
    void effect();
    return () => {
      cancelled = true;
    };
    // `reportError` is rebuilt on every App render, so depending on it would
    // turn each reported failure into another load.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [reloadToken]);

  useEffect(() => {
    return () => {
      if (armTimer.current !== null) {
        clearTimeout(armTimer.current);
      }
    };
  }, []);

  // Replaces the listing in place: clearing it first would drop the cards,
  // closing every section the user opened.
  const refresh = async () => {
    const loaded = await getInstalledContent();
    setLocations(loaded);
    setSelection((current) => pruneSelection(current, loaded));
  };

  const announce = (message: string) => {
    context.setSnackbar({
      message: (
        <span className="flex">
          <MdCheck className="w-5 h-5 mx-2" />
          {message}
        </span>
      ),
      className: "bg-emerald-600 rounded-4xl",
      timeout: 5000,
    });
  };

  const runCopy = async (request: CopyRequest) => {
    if (pending !== null || request.fileNames.length === 0) {
      return;
    }
    disarm();
    setPending(request.key);
    try {
      const copied = await copyContent(
        request.from.id,
        request.to.id,
        request.modType,
        request.fileNames,
      );
      announce(
        t("installedContentCopied", {
          count: copied,
          name: locationTitle(request.to, t),
        }),
      );
      await refresh();
    } catch (error) {
      reportError(error);
    } finally {
      setPending(null);
    }
  };

  const runDelete = async (request: DeleteRequest) => {
    setPending(request.key);
    try {
      const removed = await deleteContent(
        request.location.id,
        request.modType,
        request.fileNames,
      );
      announce(
        request.fileNames.length === 1
          ? t("installedContentDeleted", { file: request.fileNames[0] })
          : t("installedContentDeletedCount", { count: removed }),
      );
      await refresh();
    } catch (error) {
      reportError(error);
    } finally {
      setPending(null);
    }
  };

  const askDelete = (request: DeleteRequest) => {
    if (pending !== null || request.fileNames.length === 0) {
      return;
    }
    if (armedKey !== request.key) {
      if (armTimer.current !== null) {
        clearTimeout(armTimer.current);
      }
      setArmedKey(request.key);
      armTimer.current = setTimeout(() => {
        armTimer.current = null;
        setArmedKey(null);
      }, ARM_TIMEOUT_MS);
      return;
    }
    disarm();
    void runDelete(request);
  };

  const actions: ContentActions = {
    locations: locations ?? [],
    pending,
    armedKey,
    selection,
    copy: (request) => void runCopy(request),
    askDelete,
    disarm,
    select: setSelection,
  };

  return (
    <motion.div
      initial={{ y: 24, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      exit={{ y: 24, opacity: 0 }}
      className="flex flex-1 flex-col w-full transform-gpu backface-hidden will-change-[transform,opacity]"
    >
      <div className="flex flex-row items-center gap-2 mx-8 my-4">
        <h1 className="flex-1 min-w-0 font-extrabold text-2xl">
          {t("installedContent")}
        </h1>
        <Button
          onClick={() => {
            setReloadToken((token) => token + 1);
          }}
          className="flex shrink-0 items-center justify-center w-10 h-10 rounded-full bg-slate-700 text-slate-200 hover:bg-slate-600 hover:text-white"
          title={t("installedContentRefresh")}
          aria-label={t("installedContentRefresh")}
        >
          <MdRefresh aria-hidden="true" className="w-5 h-5" />
        </Button>
      </div>
      {locations === undefined ? (
        <div className="flex flex-1 items-center justify-center">
          <CircularProgress />
        </div>
      ) : locations.length === 0 ? null : (
        <div className="bg-slate-800 rounded-4xl mx-6 my-4">
          {locations.map((location, index) => (
            <LocationCard
              key={location.id}
              location={location}
              collapsible={index > 0}
              actions={actions}
            />
          ))}
        </div>
      )}
      <div className="h-1"></div>
    </motion.div>
  );
}
