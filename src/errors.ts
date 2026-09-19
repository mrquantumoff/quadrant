/** @format */

import type { TFunction } from "i18next";
import quadrantLocale from "./i18n";

function rawMessage(error: unknown): string {
  const message = (error as { message?: unknown } | null | undefined)?.message;
  return String(typeof message === "string" ? message : error).trim();
}

/**
 * The text to show for a caught error.
 *
 * The backend classifies failures itself (`quadrant_core::error::ErrorCode`)
 * and sends the code's i18n key, so this only translates a key and otherwise
 * keeps the raw text visible.
 */
export function describeError(error: unknown, t: TFunction): string {
  const raw = rawMessage(error);
  if (raw === "") {
    return t("errorUnknownNoDetails");
  }
  // A key never contains whitespace, so English sentences can't shadow one.
  if (!/\s/.test(raw) && quadrantLocale.exists(raw)) {
    return t(raw);
  }
  return t("errorUnknown", { details: raw });
}
