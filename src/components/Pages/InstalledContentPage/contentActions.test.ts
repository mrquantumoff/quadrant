/** @format */

import { describe, expect, it } from "vitest";
import { ContentFile, ContentLocation, ModType } from "../../../intefaces";
import {
  controlKey,
  copyTargets,
  filesOf,
  pruneSelection,
  selectedIn,
  selectionKey,
  toggleSelection,
} from "./contentActions";

function file(fileName: string): ContentFile {
  return { fileName, size: 1024, modified: 0, isDirectory: false };
}

function location(over: Partial<ContentLocation>): ContentLocation {
  return {
    id: "minecraft",
    kind: "minecraft",
    name: "",
    path: "/home/me/.minecraft",
    resourcePacks: [],
    shaderPacks: [],
    ...over,
  };
}

const minecraft = location({ resourcePacks: [file("Faithful.zip")] });
const survival = location({
  id: "prism:1",
  kind: "prism",
  name: "Survival",
  resourcePacks: [file("Faithful.zip")],
  shaderPacks: [file("BSL.zip")],
});
const modded = location({ id: "prism:2", kind: "prism", name: "Modded" });

describe("filesOf", () => {
  it("answers with the section matching the kind of pack", () => {
    expect(filesOf(survival, ModType.ResourcePack)).toEqual([
      file("Faithful.zip"),
    ]);
    expect(filesOf(survival, ModType.ShaderPack)).toEqual([file("BSL.zip")]);
  });

  it("holds nothing for a kind no location stores", () => {
    expect(filesOf(survival, ModType.Mod)).toEqual([]);
  });
});

describe("copyTargets", () => {
  it("offers every location except the source, in listed order", () => {
    const targets = copyTargets(
      [minecraft, survival, modded],
      "minecraft",
      ModType.ResourcePack,
      ["Faithful.zip"],
    );
    expect(targets.map((target) => target.location.id)).toEqual([
      "prism:1",
      "prism:2",
    ]);
  });

  it("counts a name the destination already holds as nothing to do", () => {
    const [target] = copyTargets(
      [minecraft, survival],
      "minecraft",
      ModType.ResourcePack,
      ["Faithful.zip"],
    );
    expect(target.missing).toEqual([]);
  });

  it("keeps the names the destination is missing, in request order", () => {
    const [target] = copyTargets(
      [minecraft, survival],
      "minecraft",
      ModType.ResourcePack,
      ["Faithful.zip", "Bare.zip", "Alpha.zip"],
    );
    expect(target.missing).toEqual(["Bare.zip", "Alpha.zip"]);
  });

  it("matches names within one section, not across them", () => {
    // Survival has BSL.zip as a shader; that must not hide a resource pack
    // of the same name.
    const [target] = copyTargets(
      [minecraft, survival],
      "minecraft",
      ModType.ResourcePack,
      ["BSL.zip"],
    );
    expect(target.missing).toEqual(["BSL.zip"]);
  });

  it("offers nothing when the source is the only location", () => {
    expect(
      copyTargets([minecraft], "minecraft", ModType.ResourcePack, [
        "Faithful.zip",
      ]),
    ).toEqual([]);
  });

  it("reports an empty destination as missing everything", () => {
    const [target] = copyTargets(
      [minecraft, modded],
      "minecraft",
      ModType.ShaderPack,
      ["BSL.zip", "Complementary.zip"],
    );
    expect(target.location.name).toBe("Modded");
    expect(target.missing).toEqual(["BSL.zip", "Complementary.zip"]);
  });
});

describe("controlKey", () => {
  it("tells a file's control apart from its section's bulk controls", () => {
    expect(controlKey("minecraft", ModType.ResourcePack)).not.toBe(
      controlKey("minecraft", ModType.ResourcePack, "Faithful.zip"),
    );
    expect(selectionKey("minecraft", ModType.ResourcePack)).not.toBe(
      controlKey("minecraft", ModType.ResourcePack, "Faithful.zip"),
    );
  });

  it("tells the same file apart across sections and locations", () => {
    const here = controlKey("minecraft", ModType.ResourcePack, "Faithful.zip");
    expect(here).not.toBe(
      controlKey("prism:1", ModType.ResourcePack, "Faithful.zip"),
    );
    expect(here).not.toBe(
      controlKey("minecraft", ModType.ShaderPack, "Faithful.zip"),
    );
  });
});

describe("selection", () => {
  const packs = {
    locationId: "minecraft",
    modType: ModType.ResourcePack,
    fileNames: ["Faithful.zip", "Alpha.zip"],
  };

  it("reads back only in the section it was made in", () => {
    expect(selectedIn(packs, "minecraft", ModType.ResourcePack)).toEqual([
      "Faithful.zip",
      "Alpha.zip",
    ]);
    expect(selectedIn(packs, "minecraft", ModType.ShaderPack)).toEqual([]);
    expect(selectedIn(packs, "prism:1", ModType.ResourcePack)).toEqual([]);
    expect(selectedIn(null, "minecraft", ModType.ResourcePack)).toEqual([]);
  });

  it("adds a file in ticking order and removes it on a second tick", () => {
    const one = toggleSelection(
      null,
      "minecraft",
      ModType.ResourcePack,
      "Faithful.zip",
    );
    const two = toggleSelection(
      one,
      "minecraft",
      ModType.ResourcePack,
      "Alpha.zip",
    );
    expect(two?.fileNames).toEqual(["Faithful.zip", "Alpha.zip"]);
    expect(
      toggleSelection(two, "minecraft", ModType.ResourcePack, "Faithful.zip")
        ?.fileNames,
    ).toEqual(["Alpha.zip"]);
  });

  it("drops the whole selection once the last file is unticked", () => {
    const one = toggleSelection(
      null,
      "minecraft",
      ModType.ResourcePack,
      "Faithful.zip",
    );
    expect(
      toggleSelection(one, "minecraft", ModType.ResourcePack, "Faithful.zip"),
    ).toBeNull();
  });

  it("replaces a selection made in another section", () => {
    const moved = toggleSelection(
      packs,
      "prism:1",
      ModType.ShaderPack,
      "BSL.zip",
    );
    expect(moved).toEqual({
      locationId: "prism:1",
      modType: ModType.ShaderPack,
      fileNames: ["BSL.zip"],
    });
  });

  it("forgets names a reload no longer reports", () => {
    expect(pruneSelection(packs, [minecraft, survival])).toEqual({
      locationId: "minecraft",
      modType: ModType.ResourcePack,
      fileNames: ["Faithful.zip"],
    });
  });

  it("drops a selection whose files are all gone", () => {
    expect(pruneSelection(packs, [location({}), survival])).toBeNull();
  });

  it("drops a selection whose location is gone", () => {
    expect(pruneSelection(packs, [survival])).toBeNull();
  });

  it("leaves an empty selection empty", () => {
    expect(pruneSelection(null, [minecraft])).toBeNull();
  });
});
