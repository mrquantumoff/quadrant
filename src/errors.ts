/** @format */

import type { TFunction } from "i18next";
import quadrantLocale from "./i18n";

/**
 * Backend errors arrive as opaque strings: some are i18n keys, the rest are
 * reqwest/io/anyhow text. Order matters, the first match wins, so narrower
 * patterns come before the broad transport ones.
 */
export const ERROR_RULES: { pattern: RegExp; key: string }[] = [
  {
    pattern: /builder error|relative URL without a base|empty host/i,
    key: "errorInvalidRequest",
  },
  { pattern: /timed out|timeout/i, key: "errorTimeout" },
  { pattern: /\b429\b|too many requests/i, key: "errorRateLimited" },
  { pattern: /\b40[13]\b|unauthorized|forbidden/i, key: "errorForbidden" },
  { pattern: /\b404\b/i, key: "errorNotFound" },
  {
    pattern: /\b5\d\d\b.*(server|gateway|unavailable)|server error/i,
    key: "errorServer",
  },
  {
    pattern:
      /error sending request|dns error|failed to lookup|connection (refused|reset|closed|aborted)|network/i,
    key: "errorNetwork",
  },
  {
    pattern:
      /error decoding response body|missing field|invalid type|expected .* at line/i,
    key: "errorBadResponse",
  },
  { pattern: /sha-?1 verification/i, key: "errorChecksum" },
  {
    pattern:
      /untrusted download host|unsupported download url scheme|unsafe download file name|invalid download file name|download url has no file name/i,
    key: "errorUnsafeDownload",
  },
  { pattern: /curseforge is not enabled/i, key: "errorCurseforgeDisabled" },
  {
    pattern:
      /modpack (not found|doesn't exist|does not exist)|no modpack found/i,
    key: "errorModpackMissing",
  },
  { pattern: /modpack exists/i, key: "errorModpackExists" },
  { pattern: /invalid modpack name/i, key: "errorInvalidModpackName" },
  { pattern: /mod already registered/i, key: "errorModAlreadyRegistered" },
  {
    pattern: /os error (5|13)\b|permission denied|access is denied/i,
    key: "errorFileAccess",
  },
  { pattern: /os error 32\b|used by another process/i, key: "errorFileInUse" },
  { pattern: /os error (28|112)\b|no space left/i, key: "errorDiskFull" },
  { pattern: /keyring is locked/i, key: "errorKeyringLocked" },
  {
    pattern:
      /mcFolder is not configured|default minecraft folder is unavailable/i,
    key: "errorNoMinecraftFolder",
  },
  { pattern: /no account token|no refresh token/i, key: "errorSignedOut" },
  { pattern: /is busy/i, key: "errorBusy" },
];

function rawMessage(error: unknown): string {
  if (typeof error === "string") {
    return error.trim();
  }
  if (error instanceof Error) {
    return error.message.trim();
  }
  if (
    typeof error === "object" &&
    error !== null &&
    "message" in error &&
    typeof (error as { message: unknown }).message === "string"
  ) {
    return (error as { message: string }).message.trim();
  }
  return String(error).trim();
}

export function describeError(error: unknown, t: TFunction): string {
  const raw = rawMessage(error);
  if (raw === "") {
    return t("errorUnknownNoDetails");
  }
  // A key never contains whitespace, so English sentences can't shadow one.
  if (!/\s/.test(raw) && quadrantLocale.exists(raw)) {
    return t(raw);
  }
  const rule = ERROR_RULES.find(({ pattern }) => pattern.test(raw));
  if (rule) {
    return t(rule.key);
  }
  return t("errorUnknown", { details: raw });
}
