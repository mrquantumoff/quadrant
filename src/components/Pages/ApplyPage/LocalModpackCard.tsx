/** @format */

import { useContext } from "react";
import {
  AccountInfo,
  ContentContext,
  LocalModpack,
  SyncContext,
  SyncedModpack,
} from "../../../intefaces";
import {
  applyModpack,
  deleteModpack,
  exportModpack,
  shareModpack,
  syncModpack,
} from "../../../tools";
import { useTranslation } from "react-i18next";
import Button from "../../core/Button";
import { motion } from "motion/react";
import {
  MdArchive,
  MdCheck,
  MdDelete,
  MdEdit,
  MdInfo,
  MdShare,
  MdSync,
} from "react-icons/md";
import ModpackView from "../../shared/Pages/ModpackView";
import CloudMembersPanel from "./CloudMembersPanel";
import ModpackBadges from "./ModpackBadges";
import { formatSyncDate } from "./syncDates";

export interface LocalModpackCardProps {
  modpack: LocalModpack;
  /** The Quadrant Sync record this modpack is paired with, if any. */
  synced?: SyncedModpack;
  accountInfo?: AccountInfo | null;
  onChanged: () => void | Promise<void>;
  onEdit: (modpack: LocalModpack) => void;
}

export default function LocalModpackCard({
  modpack,
  synced,
  accountInfo = null,
  onChanged,
  onEdit,
}: LocalModpackCardProps) {
  const { t } = useTranslation();
  const context = useContext(ContentContext);
  const syncContext = useContext(SyncContext);

  const dateString = t("localSyncDate", {
    date: formatSyncDate(modpack.lastSynced),
  });
  return (
    <motion.div
      initial={{ opacity: 0, y: 24 }}
      animate={{ y: 0, opacity: 1 }}
      whileHover={{ y: -5 }}
      transition={{ duration: 0.15, ease: "linear" }}
      exit={{
        opacity: 0,
        y: -24,
      }}
      className="flex flex-col bg-slate-900 hover:bg-slate-950 p-4 rounded-4xl mx-5 my-5 h-max hover:shadow-lg hover:shadow-slate-950 transform-gpu backface-hidden will-change-[transform,opacity]"
    >
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
        <h1 className="text-2xl font-extrabold max-w-full w-fit">
          {modpack.name}
        </h1>
        <ModpackBadges installed synced={synced !== undefined} />
      </div>
      <p className="text-md text-slate-400 ">
        {modpack.version} | {modpack.modLoader} |{" "}
        {t("modCount", { amount: modpack.mods.length })}{" "}
        {modpack.lastSynced !== 0 && <span>| {dateString}</span>}
        {synced && (
          <span>
            {" "}
            | {t("cloudSyncDate", { date: formatSyncDate(synced.last_synced) })}
          </span>
        )}
      </p>
      <div className="my-2 flex overflow-x-auto flex-wrap h-max flex-row items-center text-sm justify-start text-center w-full">
        <Button
          onClick={async () => {
            if (modpack.isApplied) {
              return;
            }
            try {
              await applyModpack(modpack.name);
              await onChanged();
              context.setSnackbar({
                message: (
                  <span className="flex">
                    <MdCheck className="w-5 h-5 mx-2" />
                    {t("setModpackSuccess")}
                  </span>
                ),
                className: "bg-emerald-600 rounded-4xl",
                timeout: 5000,
              });
            } catch (e: any) {
              console.error(e);
              context.setSnackbar({
                message: t("setModpackFailed"),
                className: "bg-red-700 rounded-4xl",
                timeout: 5000,
              });
            }
          }}
          className={
            modpack.isApplied
              ? "flex items-center self-center bg-emerald-900 cursor-default w-max px-4 h-10 justify-center m-2"
              : "flex items-center self-center bg-emerald-600 hover:bg-emerald-700 px-4 w-max h-10 justify-center m-2"
          }
        >
          {modpack.isApplied ? t("applied") : t("apply")}
          <MdCheck className="w-5 h-5 mx-2" />
        </Button>
        <Button
          onClick={async () => {
            try {
              await shareModpack(modpack.name);
            } catch (e: any) {
              console.error(e);
              context.setSnackbar({
                message: t(e),
                className: "bg-red-700 rounded-4xl",
                timeout: 5000,
              });
            }
          }}
          className={
            "flex items-center self-center bg-blue-600 hover:bg-blue-700 px-4 m-2 w-max h-10 justify-center"
          }
        >
          {t("share")}
          <MdShare className="w-5 h-5 mx-2" />
        </Button>
        <Button
          onClick={async () => {
            try {
              await syncModpack(modpack, true);
              // The push creates or updates the cloud record; nothing else
              // tells the cloud list about it.
              syncContext.refreshSyncedModpacks();
              context.setSnackbar({
                message: (
                  <span className="flex">
                    <MdCheck className="w-5 h-5 mx-2" />
                    {t("modpackUpdated")}
                  </span>
                ),
                className: "bg-emerald-600 rounded-4xl",
                timeout: 5000,
              });
              await onChanged();
            } catch (e: any) {
              console.error(e);
              context.setSnackbar({
                message: t(e),
                className: "bg-red-700 rounded-4xl",
                timeout: 5000,
              });
            }
          }}
          className={
            "flex items-center px-4 self-center bg-emerald-600 hover:bg-emerald-700 m-2 w-max h-10 justify-center"
          }
        >
          {t("sync")}
          <MdSync className="w-5 h-5 ml-2" />
        </Button>
        <Button
          onClick={async () => {
            onEdit(modpack);
          }}
          className={
            "flex items-center self-center bg-blue-600 hover:bg-blue-700 px-4 m-2 w-max h-10 justify-center"
          }
        >
          {t("update")}
          <MdEdit className="w-5 h-5 mx-2" />
        </Button>
        <Button
          onClick={async () => {
            try {
              exportModpack(modpack.name);
            } catch (e: any) {
              console.error(e);
              context.setSnackbar({
                message: t(e),
                className: "bg-red-700 rounded-4xl",
                timeout: 5000,
              });
            }
          }}
          className={
            "flex items-center self-center px-4 bg-slate-800 hover:bg-slate-700 m-2 w-max h-10 justify-center"
          }
        >
          {t("export")}
          <MdArchive className="w-5 h-5 mx-2" />
        </Button>
        <Button
          onClick={async () => {
            try {
              await deleteModpack(modpack.name);
              await onChanged();
              context.setSnackbar({
                message: <MdDelete className="w-5 h-5 mx-2" />,
                className: "bg-emerald-600 rounded-4xl",
                timeout: 5000,
              });
            } catch (e: any) {
              console.error(e);
              context.setSnackbar({
                message: t("unknown"),
                className: "bg-red-700 rounded-4xl",
                timeout: 5000,
              });
            }
          }}
          className={
            "flex items-center self-center bg-slate-800 hover:bg-red-700 px-4  w-max h-10 m-2 justify-center"
          }
        >
          {t("delete")}
          <MdDelete className="w-5 h-5 mx-2" />
        </Button>
        <Button
          onClick={async () => {
            const randomString = Math.random().toString(36).substring(2, 10);
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
                  unknownMods={modpack.unknownMods}
                ></ModpackView>
              ),
            });
          }}
          className={
            "flex items-center self-center bg-slate-800 hover:bg-slate-700 px-4 w-max m-2 h-10 justify-center"
          }
        >
          {t("details")}
          <MdInfo className="w-5 h-5 mx-2" />
        </Button>
      </div>
      {synced && (
        <CloudMembersPanel
          modpack={synced}
          accountInfo={accountInfo}
          localName={modpack.name}
        />
      )}
    </motion.div>
  );
}
