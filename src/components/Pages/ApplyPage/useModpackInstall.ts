/** @format */

import { useContext, useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { ContentContext, InstalledModpack } from "../../../intefaces";
import { installModpack } from "../../../tools";
import { invoke, listen } from "../../../desktop";

export interface ModpackSyncTarget {
  syncedAt: number;
  modpackId: string;
}

export interface ModpackInstallState {
  /** Starts the install. No-op while one is already running. */
  install: () => Promise<void>;
  /** 0..1 while installing, 1 when idle. */
  progress: number;
}

/**
 * Installs a modpack manifest into the local modpacks folder, reporting the
 * backend's download progress and a snackbar on completion or failure. When a
 * sync target is given the local sync metadata is stamped afterwards so the
 * pack pairs with its Quadrant Sync record.
 */
export function useModpackInstall(
  modpack: InstalledModpack,
  syncTarget?: ModpackSyncTarget,
): ModpackInstallState {
  const { t } = useTranslation();
  const context = useContext(ContentContext);
  const [progress, setProgress] = useState(1);
  const requestedRef = useRef(false);

  useEffect(() => {
    let isUnmounted = false;
    let unlisten: (() => void | Promise<void>) | null = null;

    const attachListener = async () => {
      unlisten = await listen("modpackDownloadProgress", (event: any) => {
        // The event is global; only the instance that started the install
        // should reflect it.
        if (isUnmounted || !requestedRef.current) {
          return;
        }
        setProgress(event.payload);
        if (event.payload === 1) {
          requestedRef.current = false;
          context.setSnackbar({
            className: "bg-emerald-600",
            message: t("downloadSuccess"),
            timeout: 5000,
          });
        }
      });

      if (isUnmounted && unlisten) {
        await unlisten();
        unlisten = null;
      }
    };

    attachListener().catch(console.error);

    return () => {
      isUnmounted = true;
      if (unlisten) {
        unlisten();
      }
    };
  }, [context, t]);

  const install = async () => {
    if (requestedRef.current) {
      return;
    }
    requestedRef.current = true;
    // Progress is driven by the backend's first event, so the label does not
    // flicker to 0% for installs that finish before any event arrives.
    try {
      await installModpack(modpack);
      if (syncTarget) {
        await invoke("set_modpack_sync_date", {
          time: syncTarget.syncedAt,
          modpack: modpack.name,
          modpackId: syncTarget.modpackId,
        });
      }
    } catch (e: any) {
      requestedRef.current = false;
      setProgress(1);
      context.setSnackbar({
        className: "bg-red-700",
        message: t(e),
        timeout: 5000,
      });
    }
  };

  return { install, progress };
}
