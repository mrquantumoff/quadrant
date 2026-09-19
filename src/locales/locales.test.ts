/** @format */

import { describe, expect, it } from "vitest";
import en from "./en.json";
import tr from "./tr.json";
import uk from "./uk.json";

const locales = { en, tr, uk } as const;
const reference = "en";

const PLURAL_SUFFIXES = ["_zero", "_one", "_two", "_few", "_many", "_other"];

/** Splits `copied_other` into `["copied", "other"]`; plain keys keep no form. */
function splitPlural(key: string): [string, string | undefined] {
  const suffix = PLURAL_SUFFIXES.find((candidate) => key.endsWith(candidate));
  return suffix
    ? [key.slice(0, -suffix.length), suffix.slice(1)]
    : [key, undefined];
}

/**
 * Every key a locale needs to say what en says. i18next picks a plural form by
 * suffix and never derives a missing one, so a language with more categories
 * than English needs a written form for each of them or it falls back to en.
 */
function expectedKeys(locale: string): string[] {
  const categories = new Intl.PluralRules(locale).resolvedOptions()
    .pluralCategories;
  const keys = new Set<string>();
  for (const key of Object.keys(locales[reference])) {
    const [base, form] = splitPlural(key);
    if (form === undefined) {
      keys.add(base);
      continue;
    }
    for (const category of categories) {
      keys.add(`${base}_${category}`);
    }
  }
  return [...keys].sort();
}

describe("locale files", () => {
  it.each(Object.keys(locales))(
    "%s carries exactly the keys en asks of it",
    (locale) => {
      const expected = expectedKeys(locale);
      const keys = Object.keys(locales[locale as keyof typeof locales]).sort();
      const missing = expected.filter((k) => !keys.includes(k));
      const extra = keys.filter((k) => !expected.includes(k));
      expect({ missing, extra }).toEqual({ missing: [], extra: [] });
    },
  );

  it.each(Object.keys(locales))("%s has no empty values", (locale) => {
    const empty = Object.entries(locales[locale as keyof typeof locales])
      .filter(([, value]) => typeof value !== "string" || value.trim() === "")
      .map(([key]) => key);
    expect(empty).toEqual([]);
  });
});
