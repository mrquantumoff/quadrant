/** @format */

import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ModLoader, ModSource, ModType, type IMod } from "../../intefaces";

const mocks = vi.hoisted(() => ({ get: vi.fn(), installMod: vi.fn() }));
vi.mock("../../tools", () => ({
  installMod: mocks.installMod,
  deleteMod: vi.fn(),
  installRemoteFile: vi.fn(),
  openIn: vi.fn(),
  registerMod: vi.fn(),
}));
vi.mock("../../desktop", () => ({
  createDesktopStore: () => mocks,
  listen: vi.fn(async () => vi.fn()),
}));
vi.mock("../Pages/ModInstallPage/ModInstallPage", () => ({
  default: () => null,
}));
import Mod from "./Mod";

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
  autoinstallable: true,
  selectable: false,
  modpack: null,
  selectUrl: null,
};

beforeEach(() => {
  vi.resetAllMocks();
  mocks.get.mockImplementation(
    async (key: string) =>
      ({
        lastUsedModpack: "Different Pack",
        lastUsedVersion: "1.12.2",
        lastUsedAPI: ModLoader.Forge,
      })[key],
  );
  mocks.installMod.mockResolvedValue(undefined);
});

describe("Mod", () => {
  it("installs search results using their explicit target instead of stale global settings", async () => {
    render(
      <Mod
        mod={mod}
        modpack={undefined}
        className=""
        installTarget={{
          name: "Selected Pack",
          version: "1.21.1",
          modLoader: ModLoader.Fabric,
        }}
      />,
    );
    await userEvent.click(screen.getByRole("button", { name: "download" }));
    expect(mocks.installMod).toHaveBeenCalledWith(
      mod.id,
      "1.21.1",
      ModLoader.Fabric,
      mod.source,
      mod.modType,
      "Selected Pack",
    );
  });

  it("allows retrying a download after reading saved settings fails", async () => {
    let failed = false;
    mocks.get.mockImplementation(async (key: string) => {
      if (key === "lastUsedAPI" && !failed) {
        failed = true;
        throw "settingsUnavailable";
      }
      return undefined;
    });
    render(<Mod mod={mod} modpack={undefined} className="" />);
    await userEvent.click(screen.getByRole("button", { name: "download" }));
    expect(mocks.installMod).not.toHaveBeenCalled();
    await userEvent.click(screen.getByRole("button", { name: "download" }));
    await waitFor(() => expect(mocks.installMod).toHaveBeenCalledTimes(1));
  });
});
