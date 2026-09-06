/** @format */

import { useTranslation } from "react-i18next";
import { MdCloud, MdCloudDone, MdComputer } from "react-icons/md";

export interface ModpackBadgesProps {
  /** Whether the modpack exists in the local modpacks folder. */
  installed: boolean;
  /** Whether the modpack has a Quadrant Sync record. */
  synced: boolean;
}

const badgeClass =
  "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-extrabold whitespace-nowrap";

/**
 * Small pills next to a modpack name: where it lives (local or cloud) and,
 * when it has a Quadrant Sync record, a Synced marker.
 */
export default function ModpackBadges({
  installed,
  synced,
}: ModpackBadgesProps) {
  const { t } = useTranslation();

  return (
    <span className="inline-flex flex-wrap items-center gap-1.5 align-middle">
      {installed ? (
        <span className={badgeClass + " bg-slate-700 text-slate-200"}>
          <MdComputer aria-hidden="true" className="w-3 h-3" />
          {t("badgeLocal")}
        </span>
      ) : (
        <span className={badgeClass + " bg-sky-500/20 text-sky-300"}>
          <MdCloud aria-hidden="true" className="w-3 h-3" />
          {t("badgeCloud")}
        </span>
      )}
      {synced && (
        <span className={badgeClass + " bg-emerald-500/15 text-emerald-400"}>
          <MdCloudDone aria-hidden="true" className="w-3 h-3" />
          {t("badgeSynced")}
        </span>
      )}
    </span>
  );
}
