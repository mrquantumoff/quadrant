/** @format */

import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  ContentContext,
  ModLoader,
  ModSource,
  ModType,
  type IMod,
} from "../../intefaces";

const mocks = vi.hoisted(() => ({
  get: vi.fn(),
  installMod: vi.fn(),
  getModpacks: vi.fn(),
}));
vi.mock("../../tools", () => ({
  installMod: mocks.installMod,
  getModpacks: mocks.getModpacks,
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

const context = {
  changePage: vi.fn(),
  changeContent: vi.fn(),
  back: vi.fn(),
  setSnackbar: vi.fn(),
  setSnackbarNoState: vi.fn(),
};

function renderCard(installed: boolean) {
  return render(
    <ContentContext.Provider value={context}>
      <Mod mod={mod} modpack={undefined} className="" installed={installed} />
    </ContentContext.Provider>,
  );
}

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
    await userEvent.click(screen.getByRole("button", { name: "Download" }));
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
    await userEvent.click(screen.getByRole("button", { name: "Download" }));
    expect(mocks.installMod).not.toHaveBeenCalled();
    await userEvent.click(screen.getByRole("button", { name: "Download" }));
    await waitFor(() => expect(mocks.installMod).toHaveBeenCalledTimes(1));
  });

  it("opens the install page instead of installing when the mod is already in the pack", async () => {
    renderCard(true);
    await userEvent.click(screen.getByRole("button", { name: "Installed" }));
    expect(context.changeContent).toHaveBeenCalled();
    expect(mocks.installMod).not.toHaveBeenCalled();
  });

  it("installs directly when the same mod is not in the pack", async () => {
    renderCard(false);
    await userEvent.click(screen.getByRole("button", { name: "Download" }));
    await waitFor(() => expect(mocks.installMod).toHaveBeenCalledTimes(1));
  });

  it("hands the re-read modpacks to onInstalled after a one-click install", async () => {
    const packs = [{ name: "Selected Pack" }];
    mocks.getModpacks.mockResolvedValue(packs);
    const onInstalled = vi.fn();
    render(
      <Mod mod={mod} modpack={undefined} className="" onInstalled={onInstalled} />,
    );
    await userEvent.click(screen.getByRole("button", { name: "Download" }));
    await waitFor(() => expect(onInstalled).toHaveBeenCalledWith(packs));
  });

  it("does not report an install that failed", async () => {
    mocks.installMod.mockRejectedValue("noVersion");
    const onInstalled = vi.fn();
    render(
      <ContentContext.Provider value={context}>
        <Mod
          mod={mod}
          modpack={undefined}
          className=""
          onInstalled={onInstalled}
        />
      </ContentContext.Provider>,
    );
    await userEvent.click(screen.getByRole("button", { name: "Download" }));
    await waitFor(() => expect(context.setSnackbar).toHaveBeenCalled());
    expect(onInstalled).not.toHaveBeenCalled();
  });

  it("explains a blocked third-party download instead of echoing the key", async () => {
    mocks.installMod.mockRejectedValue("thirdPartyDownloadDisabled");
    renderCard(false);

    await userEvent.click(screen.getByRole("button", { name: "Download" }));

    await waitFor(() =>
      expect(context.setSnackbar).toHaveBeenCalledWith(
        expect.objectContaining({
          message:
            "This mod's author doesn't allow downloads from third-party apps. Open it in the browser to download it manually.",
        }),
      ),
    );
  });
});
