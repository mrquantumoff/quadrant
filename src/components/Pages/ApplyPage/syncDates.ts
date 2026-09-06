/** @format */

import quadrantLocale from "../../../i18n";

// Timestamps below this are in seconds (older records); newer ones are in ms.
const SECONDS_THRESHOLD = 170406720000;

/** Formats a local or cloud sync timestamp, whichever unit it was stored in. */
export function formatSyncDate(timestamp: number): string {
  const multiplier = timestamp <= SECONDS_THRESHOLD ? 1000 : 1;
  return new Intl.DateTimeFormat(quadrantLocale.language, {
    weekday: "long",
    day: "2-digit",
    month: "2-digit",
    year: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(new Date(timestamp * multiplier));
}
