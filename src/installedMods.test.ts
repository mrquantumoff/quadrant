/** @format */

import { describe, expect, it } from "vitest";
import { isInstalledIn } from "./installedMods";
import { ModSource, ModType, type LocalMod } from "./intefaces";
import sameModCases from "../src-tauri/crates/quadrant-core/testdata/same_mod_cases.json";

const pack = (mods: LocalMod[]) => ({ mods });

function installed(over: Partial<LocalMod>): LocalMod {
  return {
    id: "sodium",
    downloadUrl: "https://example.com/sodium.jar",
    source: ModSource.Modrinth,
    ...over,
  };
}

const sodium = {
  id: "sodium",
  source: ModSource.Modrinth,
  slug: "sodium",
  modType: ModType.Mod,
};

describe("isInstalledIn", () => {
  // The same table drives `is_same_mod` in quadrant-core, so the search badge
  // and what an install replaces cannot drift apart.
  it.each(sameModCases)("agrees with the backend: $name", ({ a, b, same }) => {
    const asMod = (entry: typeof a) => ({
      ...entry,
      source: entry.source as ModSource,
      modType: ModType.Mod,
    });
    const asInstalled = (entry: typeof a) =>
      installed({ ...entry, source: entry.source as ModSource });

    expect(isInstalledIn(asMod(a), pack([asInstalled(b)]))).toBe(same);
    expect(isInstalledIn(asMod(b), pack([asInstalled(a)]))).toBe(same);
  });

  it("matches an entry with the same id from the same source", () => {
    expect(isInstalledIn(sodium, pack([installed({})]))).toBe(true);
  });

  // Mirrors is_same_mod in quadrant-core: an install replaces by id alone.
  it("matches the same id regardless of source", () => {
    expect(
      isInstalledIn(
        { ...sodium, slug: "" },
        pack([installed({ source: ModSource.CurseForge })]),
      ),
    ).toBe(true);
  });

  it("does not match a shared slug within one provider", () => {
    expect(
      isInstalledIn(
        { ...sodium, id: "sodium-fork" },
        pack([installed({ slug: "sodium" })]),
      ),
    ).toBe(false);
  });

  it("matches the same slug installed from the other provider", () => {
    expect(
      isInstalledIn(
        sodium,
        pack([
          installed({
            id: "394468",
            source: ModSource.CurseForge,
            slug: "Sodium",
          }),
        ]),
      ),
    ).toBe(true);
  });

  it("never matches on an empty slug", () => {
    expect(
      isInstalledIn(
        { ...sodium, id: "iris", slug: "" },
        pack([installed({ id: "sodium", slug: "" })]),
      ),
    ).toBe(false);
  });

  it("ignores content that is not a mod", () => {
    expect(
      isInstalledIn(
        { ...sodium, modType: ModType.ResourcePack },
        pack([installed({})]),
      ),
    ).toBe(false);
  });

  it("reports false when there is no modpack", () => {
    expect(isInstalledIn(sodium, undefined)).toBe(false);
  });
});
