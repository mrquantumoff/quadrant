/** @format */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act, render, waitFor } from "@testing-library/react";
import { IMod, ModLoader, ModSource, ModType } from "../../../intefaces";

const getMod = vi.fn();
const identifyUnknownMods = vi.fn();

vi.mock("../../../tools", () => ({
  getMod: (...a: unknown[]) => getMod(...a),
  getModUpdate: vi.fn(),
  identifyUnknownMods: (...a: unknown[]) => identifyUnknownMods(...a),
}));

// The Mod card pulls in the desktop store and install flow; a marker is enough
// to prove which mods were resolved.
vi.mock("../Mod", () => ({
  default: ({ mod }: { mod: IMod }) => <div data-testid="mod">{mod.name}</div>,
}));

import ModpackView from "./ModpackView";

function fetched(id: string): IMod {
  return {
    name: id,
    id,
    downloadCount: 0,
    version: "1.0",
    dateModified: "",
    modType: ModType.Mod,
    source: ModSource.Modrinth,
    slug: id,
    thumbnailUrls: [],
    url: "",
    description: "",
    license: "",
    modIconUrl: "",
    downloadable: false,
    showPreviousVersion: false,
    newVersion: null,
    deleteable: true,
    autoinstallable: false,
    selectable: false,
    modpack: "Pack",
    selectUrl: null,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  getMod.mockImplementation(async (args: { id: string }) => fetched(args.id));
  identifyUnknownMods.mockResolvedValue([]);
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("ModpackView", () => {
  it("resolves each installed mod exactly once on mount", async () => {
    render(
      <ModpackView
        name="Pack"
        version="1.20.1"
        modLoader={ModLoader.Fabric}
        isApplied={false}
        lastSynced={0}
        unknownMods={false}
        mods={[
          { id: "sodium", downloadUrl: "", source: ModSource.Modrinth },
          { id: "lithium", downloadUrl: "", source: ModSource.Modrinth },
        ]}
      />,
    );

    await waitFor(() => expect(getMod).toHaveBeenCalledTimes(2));
    // Let any duplicate mount effect settle before asserting the final count.
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 20));
    });
    expect(getMod).toHaveBeenCalledTimes(2);
    expect(getMod.mock.calls.map((call) => call[0].id).sort()).toEqual([
      "lithium",
      "sodium",
    ]);
  });
});
