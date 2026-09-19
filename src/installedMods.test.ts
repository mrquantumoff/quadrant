/** @format */

import { describe, expect, it } from "vitest";
import { isInstalledIn } from "./installedMods";
import {
  ModLoader,
  ModSource,
  ModType,
  type LocalMod,
  type LocalModpack,
} from "./intefaces";

function pack(mods: LocalMod[]): LocalModpack {
  return {
    name: "alpha",
    version: "1.21.1",
    modLoader: ModLoader.Fabric,
    isApplied: true,
    lastSynced: 0,
    mods,
    unknownMods: false,
  };
}

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
  it("matches an entry with the same id from the same source", () => {
    expect(isInstalledIn(sodium, pack([installed({})]))).toBe(true);
  });

  it("does not match the same id from a different source without slugs", () => {
    expect(
      isInstalledIn(
        { ...sodium, slug: "" },
        pack([installed({ source: ModSource.CurseForge })]),
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
