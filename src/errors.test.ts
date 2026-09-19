/** @format */

import { describe, expect, it } from "vitest";
import { ERROR_RULES, describeError } from "./errors";
import quadrantLocale from "./i18n";
import en from "./locales/en.json";
import tr from "./locales/tr.json";
import uk from "./locales/uk.json";

const t = quadrantLocale.t;

function describeRaw(raw: unknown): string {
  return describeError(raw, t);
}

describe("describeError normalization", () => {
  it("takes a string error as-is", () => {
    expect(describeRaw("thirdPartyDownloadDisabled")).toBe(
      en.thirdPartyDownloadDisabled,
    );
  });

  it("reads the message of an Error", () => {
    expect(describeRaw(new Error("thirdPartyDownloadDisabled"))).toBe(
      en.thirdPartyDownloadDisabled,
    );
  });

  it("reads a string message off a plain object", () => {
    expect(describeRaw({ message: "noVersion" })).toBe(en.noVersion);
  });

  it("stringifies anything else", () => {
    expect(describeRaw(42)).toBe(
      en.errorUnknown.replace("{{details}}", "42"),
    );
  });

  it("ignores surrounding whitespace", () => {
    expect(describeRaw("  noVersion  ")).toBe(en.noVersion);
  });

  it("falls back without details when there is nothing to show", () => {
    expect(describeRaw("   ")).toBe(en.errorUnknownNoDetails);
  });

  it("does not treat a non-string message as the message", () => {
    expect(describeRaw({ message: 7 })).toBe(
      en.errorUnknown.replace("{{details}}", "[object Object]"),
    );
  });
});

describe("describeError key passthrough", () => {
  it.each([
    "thirdPartyDownloadDisabled",
    "noVersion",
    "unsupportedDownload",
    "modpackRequired",
    "enableDataSharing",
  ])("translates the existing key %s", (key) => {
    expect(describeRaw(key)).toBe(en[key as keyof typeof en]);
  });

  it("does not treat an unknown single word as a key", () => {
    expect(describeRaw("kaboom")).toBe(
      en.errorUnknown.replace("{{details}}", "kaboom"),
    );
  });
});

describe("describeError rules", () => {
  const cases: [string, string][] = [
    ["builder error: relative URL without a base", "errorInvalidRequest"],
    [
      "error sending request for url (https://cdn.modrinth.com/data/x.jar): operation timed out",
      "errorTimeout",
    ],
    [
      "HTTP status client error (429 Too Many Requests) for url (https://api.curseforge.com/v1/mods/search)",
      "errorRateLimited",
    ],
    [
      "HTTP status client error (403 Forbidden) for url (https://api.curseforge.com/v1/mods/1234/files)",
      "errorForbidden",
    ],
    [
      "HTTP status client error (404 Not Found) for url (https://api.modrinth.com/v2/project/nope)",
      "errorNotFound",
    ],
    [
      "HTTP status server error (503 Service Unavailable) for url (https://api.modrinth.com/v2/search)",
      "errorServer",
    ],
    [
      "error sending request for url (https://api.modrinth.com/v2/search)",
      "errorNetwork",
    ],
    [
      "error decoding response body: missing field `downloadUrl` at line 1 column 512",
      "errorBadResponse",
    ],
    ["Downloaded file failed SHA-1 verification", "errorChecksum"],
    ["Untrusted download host", "errorUnsafeDownload"],
    ["Unsupported download URL scheme", "errorUnsafeDownload"],
    ["Download URL has no file name", "errorUnsafeDownload"],
    ["CurseForge is not enabled", "errorCurseforgeDisabled"],
    ["Modpack not found", "errorModpackMissing"],
    ["Modpack doesn't exist", "errorModpackMissing"],
    ["No modpack found", "errorModpackMissing"],
    ["Modpack exists", "errorModpackExists"],
    ["Invalid modpack name", "errorInvalidModpackName"],
    ["Mod already registered", "errorModAlreadyRegistered"],
    ["Access is denied. (os error 5)", "errorFileAccess"],
    ["Permission denied (os error 13)", "errorFileAccess"],
    [
      "The process cannot access the file because it is being used by another process. (os error 32)",
      "errorFileInUse",
    ],
    ["No space left on device (os error 28)", "errorDiskFull"],
    ["There is not enough space on the disk. (os error 112)", "errorDiskFull"],
    ["keyring is locked", "errorKeyringLocked"],
    ["mcFolder is not configured", "errorNoMinecraftFolder"],
    ["default Minecraft folder is unavailable", "errorNoMinecraftFolder"],
    ["No account token", "errorSignedOut"],
    ["No refresh token", "errorSignedOut"],
    ["runtime state is busy", "errorBusy"],
    ["settings store is busy", "errorBusy"],
  ];

  it.each(cases)("maps %s to %s", (raw, key) => {
    expect(describeRaw(raw)).toBe(en[key as keyof typeof en]);
  });
});

describe("describeError rule ordering", () => {
  it("prefers the 404 status over the transport wrapper around it", () => {
    expect(
      describeRaw(
        "error sending request for url (https://api.modrinth.com/v2/project/nope): HTTP status client error (404 Not Found)",
      ),
    ).toBe(en.errorNotFound);
  });

  it("prefers a timeout over the transport wrapper around it", () => {
    expect(
      describeRaw(
        "error sending request for url (https://api.modrinth.com/v2/search): operation timed out",
      ),
    ).toBe(en.errorTimeout);
  });

  it("prefers the modpack-missing rule over a bare 5xx-looking number", () => {
    expect(describeRaw("Modpack not found")).toBe(en.errorModpackMissing);
  });
});

describe("describeError fallback", () => {
  it("keeps the raw text of an English sentence no rule covers", () => {
    expect(describeRaw("Modpack manifest lock poisoned")).toBe(
      en.errorUnknown.replace("{{details}}", "Modpack manifest lock poisoned"),
    );
  });
});

describe("ERROR_RULES translations", () => {
  const locales = { en, tr, uk } as const;
  const keys = [
    ...ERROR_RULES.map((rule) => rule.key),
    "errorUnknown",
    "errorUnknownNoDetails",
    "thirdPartyDownloadDisabled",
    "modpackRequired",
  ];

  it.each(Object.keys(locales))("%s translates every rule key", (locale) => {
    const table = locales[locale as keyof typeof locales] as Record<
      string,
      string
    >;
    const missing = keys.filter((key) => typeof table[key] !== "string");
    expect(missing).toEqual([]);
  });

  it("has no duplicate keys in the table", () => {
    const seen = ERROR_RULES.map((rule) => rule.key);
    expect(new Set(seen).size).toBe(seen.length);
  });
});
