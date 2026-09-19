/** @format */

import { describe, expect, it } from "vitest";
import { ContentFile, ContentLocation, ModType } from "../../../intefaces";
import {
  controlKey,
  copyAllControlKey,
  copyTargets,
  countFiles,
  groupBySection,
  indexFileNames,
  pruneSelection,
  sectionKey,
  selectAllIn,
  selectedIn,
  selectionControlKey,
  SelectedFile,
  toggleSelection,
} from "./contentActions";

function file(fileName: string): ContentFile {
  return { fileName, size: 1024, modified: 0, isDirectory: false };
}

function location(
  over: Partial<ContentLocation> & {
    resourcePacks?: string[];
    shaderPacks?: string[];
  } = {},
): ContentLocation {
  const { resourcePacks = [], shaderPacks = [], ...rest } = over;
  return {
    id: "minecraft",
    kind: "minecraft",
    name: "",
    path: "/home/me/.minecraft",
    sections: [
      { modType: ModType.ResourcePack, files: resourcePacks.map(file) },
      { modType: ModType.ShaderPack, files: shaderPacks.map(file) },
    ],
    ...rest,
  };
}

const minecraft = location({ resourcePacks: ["Faithful.zip"] });
const survival = location({
  id: "prism:1",
  kind: "prism",
  name: "Survival",
  resourcePacks: ["Faithful.zip"],
  shaderPacks: ["BSL.zip"],
});
const modded = location({ id: "prism:2", kind: "prism", name: "Modded" });

const packsOf = (locationId: string) => ({
  locationId,
  modType: ModType.ResourcePack,
});
const shadersOf = (locationId: string) => ({
  locationId,
  modType: ModType.ShaderPack,
});

function ticked(
  ref: { locationId: string; modType: ModType },
  ...names: string[]
) {
  return names.map((fileName) => ({ ...ref, fileName }));
}

/** The page indexes the listing once; every target check goes through it. */
function targetsOf(locations: ContentLocation[], files: SelectedFile[]) {
  return copyTargets(locations, indexFileNames(locations), files);
}

describe("indexFileNames", () => {
  it("holds each location's names under the key of its section", () => {
    const index = indexFileNames([minecraft, survival]);
    expect(index.get(sectionKey(packsOf("prism:1")))).toEqual(
      new Set(["Faithful.zip"]),
    );
    expect(index.get(sectionKey(shadersOf("prism:1")))).toEqual(
      new Set(["BSL.zip"]),
    );
    expect(index.get(sectionKey(shadersOf("minecraft")))).toEqual(new Set());
  });

  it("knows nothing about a location that was not listed", () => {
    expect(
      indexFileNames([minecraft]).get(sectionKey(packsOf("prism:1"))),
    ).toBeUndefined();
  });

  it("holds an empty set for a section listed without its files", () => {
    const named: ContentLocation = {
      ...minecraft,
      sections: [{ modType: ModType.ResourcePack, files: [] }],
    };
    expect(
      indexFileNames([named]).get(sectionKey(packsOf("minecraft"))),
    ).toEqual(new Set());
  });
});

describe("copyTargets", () => {
  it("offers every location except the source, in listed order", () => {
    const targets = targetsOf(
      [minecraft, survival, modded],
      ticked(packsOf("minecraft"), "Faithful.zip"),
    );
    expect(targets.map((target) => target.location.id)).toEqual([
      "prism:1",
      "prism:2",
    ]);
  });

  it("counts a name the destination already holds as nothing to do", () => {
    const [target] = targetsOf(
      [minecraft, survival],
      ticked(packsOf("minecraft"), "Faithful.zip"),
    );
    expect(target.count).toBe(0);
    expect(target.groups).toEqual([]);
  });

  it("keeps the names the destination is missing, in request order", () => {
    const [target] = targetsOf(
      [minecraft, survival],
      ticked(packsOf("minecraft"), "Faithful.zip", "Bare.zip", "Alpha.zip"),
    );
    expect(target.groups).toEqual([
      { ...packsOf("minecraft"), fileNames: ["Bare.zip", "Alpha.zip"] },
    ]);
    expect(target.count).toBe(2);
  });

  it("matches names within one section, not across them", () => {
    // Survival has BSL.zip as a shader; that must not hide a resource pack
    // of the same name.
    const [target] = targetsOf(
      [minecraft, survival],
      ticked(packsOf("minecraft"), "BSL.zip"),
    );
    expect(target.count).toBe(1);
  });

  it("offers nothing when the source is the only location", () => {
    expect(
      targetsOf([minecraft], ticked(packsOf("minecraft"), "Faithful.zip")),
    ).toEqual([]);
  });

  it("reports an empty destination as missing everything", () => {
    const [target] = targetsOf(
      [minecraft, modded],
      ticked(shadersOf("minecraft"), "BSL.zip", "Complementary.zip"),
    );
    expect(target.location.name).toBe("Modded");
    expect(target.count).toBe(2);
  });

  it("treats a destination the index never saw as missing everything", () => {
    const [target] = copyTargets(
      [minecraft, survival],
      indexFileNames([minecraft]),
      ticked(packsOf("minecraft"), "Faithful.zip"),
    );
    expect(target.count).toBe(1);
  });

  it("splits a selection spanning two sections into one group each", () => {
    const [target] = targetsOf(
      [minecraft, modded],
      [
        ...ticked(packsOf("minecraft"), "Faithful.zip"),
        ...ticked(shadersOf("minecraft"), "BSL.zip"),
      ],
    );
    expect(target.groups).toEqual([
      { ...packsOf("minecraft"), fileNames: ["Faithful.zip"] },
      { ...shadersOf("minecraft"), fileNames: ["BSL.zip"] },
    ]);
    expect(target.count).toBe(2);
  });

  it("never copies a destination's own files back to it", () => {
    const targets = targetsOf(
      [minecraft, survival],
      [
        ...ticked(packsOf("minecraft"), "Alpha.zip"),
        ...ticked(shadersOf("prism:1"), "BSL.zip"),
      ],
    );
    const toSurvival = targets.find(
      (target) => target.location.id === "prism:1",
    );
    expect(toSurvival?.groups).toEqual([
      { ...packsOf("minecraft"), fileNames: ["Alpha.zip"] },
    ]);
    // Minecraft is missing the shader, and never gets its own pack back.
    const toMinecraft = targets.find(
      (target) => target.location.id === "minecraft",
    );
    expect(toMinecraft?.groups).toEqual([
      { ...shadersOf("prism:1"), fileNames: ["BSL.zip"] },
    ]);
  });
});

describe("control keys", () => {
  it("tells a file's control apart from its section's bulk controls", () => {
    expect(copyAllControlKey(packsOf("minecraft"))).not.toBe(
      controlKey(packsOf("minecraft"), "Faithful.zip"),
    );
    expect(selectionControlKey).not.toBe(
      controlKey(packsOf("minecraft"), "Faithful.zip"),
    );
  });

  it("tells the same file apart across sections and locations", () => {
    const here = controlKey(packsOf("minecraft"), "Faithful.zip");
    expect(here).not.toBe(controlKey(packsOf("prism:1"), "Faithful.zip"));
    expect(here).not.toBe(controlKey(shadersOf("minecraft"), "Faithful.zip"));
  });

  it("keys the index by the section alone, with no control in it", () => {
    expect(sectionKey(packsOf("minecraft"))).not.toBe(
      copyAllControlKey(packsOf("minecraft")),
    );
  });
});

describe("selection", () => {
  const packs = ticked(packsOf("minecraft"), "Faithful.zip", "Alpha.zip");

  it("reads back only in the section it was made in", () => {
    expect(selectedIn(packs, packsOf("minecraft"))).toEqual([
      "Faithful.zip",
      "Alpha.zip",
    ]);
    expect(selectedIn(packs, shadersOf("minecraft"))).toEqual([]);
    expect(selectedIn(packs, packsOf("prism:1"))).toEqual([]);
    expect(selectedIn([], packsOf("minecraft"))).toEqual([]);
  });

  it("adds a file in ticking order and removes it on a second tick", () => {
    const one = toggleSelection([], {
      ...packsOf("minecraft"),
      fileName: "Faithful.zip",
    });
    const two = toggleSelection(one, {
      ...packsOf("minecraft"),
      fileName: "Alpha.zip",
    });
    expect(selectedIn(two, packsOf("minecraft"))).toEqual([
      "Faithful.zip",
      "Alpha.zip",
    ]);
    expect(
      toggleSelection(two, {
        ...packsOf("minecraft"),
        fileName: "Faithful.zip",
      }),
    ).toEqual(ticked(packsOf("minecraft"), "Alpha.zip"));
  });

  it("empties out once the last file is unticked", () => {
    const one = toggleSelection([], {
      ...packsOf("minecraft"),
      fileName: "Faithful.zip",
    });
    expect(
      toggleSelection(one, {
        ...packsOf("minecraft"),
        fileName: "Faithful.zip",
      }),
    ).toEqual([]);
  });

  it("keeps a tick made in another section", () => {
    const spanning = toggleSelection(packs, {
      ...shadersOf("prism:1"),
      fileName: "BSL.zip",
    });
    expect(spanning).toEqual([
      ...packs,
      { ...shadersOf("prism:1"), fileName: "BSL.zip" },
    ]);
    expect(selectedIn(spanning, packsOf("minecraft"))).toEqual([
      "Faithful.zip",
      "Alpha.zip",
    ]);
  });

  it("tells the same name apart in two sections", () => {
    const both = toggleSelection(ticked(packsOf("minecraft"), "BSL.zip"), {
      ...shadersOf("minecraft"),
      fileName: "BSL.zip",
    });
    expect(both).toHaveLength(2);
    expect(
      toggleSelection(both, {
        ...shadersOf("minecraft"),
        fileName: "BSL.zip",
      }),
    ).toEqual(ticked(packsOf("minecraft"), "BSL.zip"));
  });

  it("adds only the named section's files, leaving the rest ticked", () => {
    const spanning = [
      ...ticked(shadersOf("prism:1"), "BSL.zip"),
      ...ticked(packsOf("minecraft"), "Alpha.zip"),
    ];
    expect(
      selectAllIn(spanning, packsOf("minecraft"), [
        "Faithful.zip",
        "Alpha.zip",
      ]),
    ).toEqual([
      ...ticked(shadersOf("prism:1"), "BSL.zip"),
      ...ticked(packsOf("minecraft"), "Alpha.zip", "Faithful.zip"),
    ]);
  });

  it("forgets names a reload no longer reports", () => {
    expect(pruneSelection(packs, [minecraft, survival])).toEqual(
      ticked(packsOf("minecraft"), "Faithful.zip"),
    );
  });

  it("drops a tick whose location is gone", () => {
    expect(pruneSelection(packs, [survival])).toEqual([]);
  });

  it("leaves an empty selection empty", () => {
    expect(pruneSelection([], [minecraft])).toEqual([]);
  });
});

describe("groupBySection", () => {
  it("issues one request per section, in first-ticked order", () => {
    expect(
      groupBySection([
        ...ticked(shadersOf("prism:1"), "BSL.zip"),
        ...ticked(packsOf("minecraft"), "Alpha.zip"),
        ...ticked(shadersOf("prism:1"), "Complementary.zip"),
      ]),
    ).toEqual([
      {
        ...shadersOf("prism:1"),
        fileNames: ["BSL.zip", "Complementary.zip"],
      },
      { ...packsOf("minecraft"), fileNames: ["Alpha.zip"] },
    ]);
  });

  it("groups nothing out of an empty selection", () => {
    expect(groupBySection([])).toEqual([]);
  });

  it("counts every file across the groups", () => {
    expect(
      countFiles(
        groupBySection([
          ...ticked(packsOf("minecraft"), "Alpha.zip", "Beta.zip"),
          ...ticked(shadersOf("prism:1"), "BSL.zip"),
        ]),
      ),
    ).toBe(3);
  });
});
