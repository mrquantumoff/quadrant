/** @format */

import { act, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  ModLoader,
  ModSource,
  ModType,
  type IMod,
  type LocalModpack,
} from "../../../intefaces";

const mocks = vi.hoisted(() => ({
  getVersions: vi.fn(),
  getModpacks: vi.fn(),
  getModOwners: vi.fn(),
  getModDependencies: vi.fn(),
  getUserURL: vi.fn(),
  installMod: vi.fn(),
  get: vi.fn(),
  set: vi.fn(),
  save: vi.fn(),
  listen: vi.fn(),
}));
vi.mock("../../../tools", () => ({ ...mocks, openIn: vi.fn() }));
vi.mock("../../../desktop", () => ({
  createDesktopStore: () => mocks,
  listen: mocks.listen,
}));
vi.mock("../../shared/Mod", () => ({
  default: ({ mod }: { mod: IMod }) => <div>{mod.name}</div>,
}));
import ModInstallPage from "./ModInstallPage";

const mod: IMod = {
  name: "Example",
  id: "example",
  downloadCount: 0,
  version: "",
  dateModified: "",
  modType: ModType.Mod,
  source: ModSource.Modrinth,
  slug: "example",
  thumbnailUrls: [],
  url: "https://example.com",
  description: "Example mod",
  license: "MIT",
  modIconUrl: "https://example.com/icon.png",
  downloadable: true,
  showPreviousVersion: false,
  newVersion: null,
  deleteable: false,
  autoinstallable: false,
  selectable: false,
  modpack: null,
  selectUrl: null,
};
const target: LocalModpack = {
  name: "Applied Pack",
  version: "1.20.1",
  modLoader: ModLoader.Fabric,
  isApplied: true,
  lastSynced: 0,
  mods: [],
  unknownMods: false,
};

beforeEach(() => {
  vi.resetAllMocks();
  mocks.getVersions.mockResolvedValue([
    { version: "1.21.1", versionType: "release" },
  ]);
  mocks.getModpacks.mockResolvedValue([target]);
  mocks.getModOwners.mockResolvedValue([]);
  mocks.getModDependencies.mockResolvedValue([]);
  mocks.get.mockResolvedValue(undefined);
  mocks.set.mockResolvedValue(undefined);
  mocks.save.mockResolvedValue(undefined);
  mocks.listen.mockResolvedValue(vi.fn());
  mocks.installMod.mockResolvedValue(undefined);
});

describe("ModInstallPage", () => {
  it("installs into the displayed pack with its version and loader on first use", async () => {
    render(<ModInstallPage mod={mod} />);
    const download = screen.getByRole("button", { name: "download" });
    await waitFor(() => expect(download).toBeEnabled());
    expect(screen.getByRole("combobox", { name: "chooseModpack" })).toHaveValue(
      target.name,
    );
    expect(screen.getByRole("combobox", { name: "chooseVersion" })).toHaveValue(
      target.version,
    );
    await userEvent.click(download);
    expect(mocks.installMod).toHaveBeenCalledWith(
      mod.id,
      target.version,
      target.modLoader,
      mod.source,
      mod.modType,
      target.name,
      undefined,
    );
  });

  it("replaces a deleted saved pack and stale install settings with the current target", async () => {
    mocks.get.mockImplementation(
      async (key: string) =>
        ({
          lastUsedModpack: "Deleted",
          lastUsedVersion: "1.12.2",
          lastUsedAPI: ModLoader.Forge,
        })[key],
    );
    render(<ModInstallPage mod={mod} />);
    await waitFor(() =>
      expect(screen.getByRole("button", { name: "download" })).toBeEnabled(),
    );
    await userEvent.click(screen.getByRole("button", { name: "download" }));
    expect(mocks.installMod).toHaveBeenCalledWith(
      mod.id,
      target.version,
      target.modLoader,
      mod.source,
      mod.modType,
      target.name,
      undefined,
    );
  });

  it("blocks downloads until the install choices have loaded", async () => {
    let resolve!: (value: LocalModpack[]) => void;
    mocks.getModpacks.mockReturnValue(
      new Promise<LocalModpack[]>((r) => {
        resolve = r;
      }),
    );
    render(<ModInstallPage mod={mod} />);
    const download = screen.getByRole("button", { name: "download" });
    expect(download).toBeDisabled();
    await userEvent.click(download);
    expect(mocks.installMod).not.toHaveBeenCalled();
    await act(async () => resolve([target]));
    expect(download).toBeEnabled();
  });

  it("selects a concrete default version for resource packs without modpacks", async () => {
    mocks.getModpacks.mockResolvedValue([]);
    render(<ModInstallPage mod={{ ...mod, modType: ModType.ResourcePack }} />);
    const download = screen.getByRole("button", { name: "download" });
    await waitFor(() => expect(download).toBeEnabled());
    await userEvent.click(download);
    expect(mocks.installMod).toHaveBeenCalledWith(
      mod.id,
      "1.21.1",
      ModLoader.Unknown,
      mod.source,
      ModType.ResourcePack,
      "",
      undefined,
    );
  });

  it("ignores dependencies from a previously viewed mod when requests finish out of order", async () => {
    let resolve!: (value: IMod[]) => void;
    mocks.getModDependencies.mockImplementation(
      (_source: ModSource, id: string) =>
        id === mod.id
          ? new Promise<IMod[]>((r) => {
              resolve = r;
            })
          : Promise.resolve([
              { ...mod, id: "new-dep", name: "New dependency" },
            ]),
    );
    const { rerender } = render(<ModInstallPage mod={mod} />);
    rerender(<ModInstallPage mod={{ ...mod, id: "new", name: "New mod" }} />);
    await screen.findByText("New dependency");
    await act(async () => resolve([{ ...mod, name: "Stale dependency" }]));
    expect(screen.queryByText("Stale dependency")).not.toBeInTheDocument();
    expect(screen.getByText("New dependency")).toBeInTheDocument();
  });
});
