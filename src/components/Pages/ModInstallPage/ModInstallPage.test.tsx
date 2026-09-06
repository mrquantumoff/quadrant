/** @format */

import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import {
  ContentContext,
  ModLoader,
  ModSource,
  ModType,
  type IMod,
} from "../../../intefaces";

const getVersions = vi.fn();
const getModpacks = vi.fn();
const getModOwners = vi.fn();
const getModDependencies = vi.fn();
const getUserURL = vi.fn();
const installMod = vi.fn();
const openIn = vi.fn();
const storeGet = vi.fn();
const storeSet = vi.fn();
const storeSave = vi.fn();

vi.mock("../../../tools", () => ({
  getVersions: (...a: unknown[]) => getVersions(...a),
  getModpacks: (...a: unknown[]) => getModpacks(...a),
  getModOwners: (...a: unknown[]) => getModOwners(...a),
  getModDependencies: (...a: unknown[]) => getModDependencies(...a),
  getUserURL: (...a: unknown[]) => getUserURL(...a),
  installMod: (...a: unknown[]) => installMod(...a),
  openIn: (...a: unknown[]) => openIn(...a),
}));

vi.mock("../../../desktop", () => ({
  createDesktopStore: () => ({
    get: (...a: unknown[]) => storeGet(...a),
    set: (...a: unknown[]) => storeSet(...a),
    save: (...a: unknown[]) => storeSave(...a),
  }),
  listen: async () => () => {},
}));

vi.mock("../../shared/Mod", () => ({
  default: ({ mod }: { mod: IMod }) => (
    <div data-testid="mod-card">{mod.name}</div>
  ),
}));

import ModInstallPage from "./ModInstallPage";

function mod(over: Partial<IMod>): IMod {
  return {
    name: "Sodium",
    id: "sodium",
    downloadCount: 12_400_000,
    version: "",
    dateModified: "",
    modType: ModType.Mod,
    source: ModSource.Modrinth,
    slug: "",
    thumbnailUrls: [],
    url: "https://modrinth.com/mod/sodium",
    description: "A rendering engine",
    license: "LGPL-3.0",
    modIconUrl: "",
    downloadable: true,
    showPreviousVersion: false,
    newVersion: null,
    deleteable: false,
    autoinstallable: false,
    selectable: false,
    modpack: null,
    selectUrl: null,
    ...over,
  };
}

const back = vi.fn();
const setSnackbar = vi.fn();

function renderPage(props: { mod: IMod; fileId?: string }) {
  return render(
    <ContentContext.Provider
      value={{
        back,
        setSnackbar,
        changeContent: () => {},
        changePage: () => {},
        setSnackbarNoState: () => {},
      }}
    >
      <ModInstallPage {...props} />
    </ContentContext.Provider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  getVersions.mockResolvedValue([{ version: "1.21" }, { version: "1.20.1" }]);
  getModpacks.mockResolvedValue([
    { name: "Pack", version: "1.20.1", modLoader: ModLoader.Fabric },
  ]);
  getModOwners.mockResolvedValue(["jellysquid"]);
  getUserURL.mockResolvedValue("https://modrinth.com/user/jellysquid");
  getModDependencies.mockResolvedValue([]);
  installMod.mockResolvedValue(undefined);
  storeGet.mockImplementation(async (key: string) =>
    key === "lastUsedVersion"
      ? "1.21"
      : key === "lastUsedAPI"
        ? ModLoader.Fabric
        : key === "lastUsedModpack"
          ? "Pack"
          : undefined,
  );
});

describe("ModInstallPage", () => {
  it("shows header metadata and owner chips, and no dependency panel when empty", async () => {
    renderPage({ mod: mod({}) });
    expect(screen.getByRole("heading", { name: "Sodium" })).toBeTruthy();
    expect(screen.getByText("12.4M")).toBeTruthy();
    expect(screen.getByText("licensedUnder")).toBeTruthy();
    expect(await screen.findByText("jellysquid")).toBeTruthy();
    expect(screen.queryByText("dependencies")).toBeNull();
  });

  it("opens the owner page from the owner chip", async () => {
    renderPage({ mod: mod({}) });
    await userEvent.click(await screen.findByText("jellysquid"));
    expect(openIn).toHaveBeenCalledWith("https://modrinth.com/user/jellysquid");
  });

  it("lists dependencies as mod cards with a count badge", async () => {
    getModDependencies.mockResolvedValue([
      mod({ id: "fabric-api", name: "Fabric API" }),
    ]);
    renderPage({ mod: mod({}) });
    expect(await screen.findByTestId("mod-card")).toHaveTextContent(
      "Fabric API",
    );
    expect(screen.getByText("1")).toBeTruthy();
  });

  it("installs with the remembered version, loader and modpack", async () => {
    renderPage({ mod: mod({}) });
    await waitFor(() =>
      expect(
        screen.getByRole("combobox", { name: /chooseVersion/ }),
      ).toHaveValue("1.21"),
    );
    await userEvent.click(
      screen.getAllByRole("button", { name: /download/ })[0],
    );
    expect(installMod).toHaveBeenCalledWith(
      "sodium",
      "1.21",
      ModLoader.Fabric,
      ModSource.Modrinth,
      ModType.Mod,
      "Pack",
      undefined,
    );
  });

  it("hides version and loader pickers when a file is preselected", async () => {
    renderPage({ mod: mod({}), fileId: "abc" });
    await screen.findByText("jellysquid");
    expect(
      screen.queryByRole("combobox", { name: /chooseVersion/ }),
    ).toBeNull();
    expect(
      screen.queryByRole("combobox", { name: /choosePreferredAPI/ }),
    ).toBeNull();
    expect(
      screen.getByRole("combobox", { name: /chooseModpack/ }),
    ).toBeTruthy();
  });

  it("picking a modpack adopts its version and loader", async () => {
    renderPage({ mod: mod({}) });
    const picker = await screen.findByRole("combobox", {
      name: /chooseModpack/,
    });
    await userEvent.selectOptions(picker, "Pack");
    await waitFor(() =>
      expect(storeSet).toHaveBeenCalledWith("lastUsedVersion", "1.20.1"),
    );
    expect(screen.getByRole("combobox", { name: /chooseVersion/ })).toHaveValue(
      "1.20.1",
    );
  });

  it("goes back on cancel", async () => {
    renderPage({ mod: mod({}) });
    await userEvent.click(screen.getByRole("button", { name: /cancel/ }));
    expect(back).toHaveBeenCalled();
  });

  it("falls back to the target pack when the saved version is gone", async () => {
    // The remembered version is no longer offered by the provider.
    storeGet.mockImplementation(async (key: string) =>
      key === "lastUsedVersion"
        ? "1.16.5"
        : key === "lastUsedModpack"
          ? "Pack"
          : undefined,
    );
    renderPage({ mod: mod({}) });

    const picker = await screen.findByRole("combobox", {
      name: /chooseVersion/,
    });
    await waitFor(() => expect(picker).toHaveValue("1.20.1"));
    await userEvent.click(
      screen.getAllByRole("button", { name: /download/ })[0],
    );
    expect(installMod).toHaveBeenCalledWith(
      "sodium",
      "1.20.1",
      ModLoader.Fabric,
      ModSource.Modrinth,
      ModType.Mod,
      "Pack",
      undefined,
    );
  });

  it("replaces a saved pack that no longer exists with an available one", async () => {
    getModpacks.mockResolvedValue([
      { name: "Applied Pack", version: "1.20.1", modLoader: ModLoader.Fabric, isApplied: true },
    ]);
    storeGet.mockImplementation(async (key: string) =>
      key === "lastUsedModpack" ? "Deleted Pack" : undefined,
    );
    renderPage({ mod: mod({}) });

    const picker = await screen.findByRole("combobox", {
      name: /chooseModpack/,
    });
    await waitFor(() => expect(picker).toHaveValue("Applied Pack"));
    await userEvent.click(
      screen.getAllByRole("button", { name: /download/ })[0],
    );
    expect(installMod).toHaveBeenCalledWith(
      "sodium",
      "1.20.1",
      ModLoader.Fabric,
      ModSource.Modrinth,
      ModType.Mod,
      "Applied Pack",
      undefined,
    );
  });

  it("blocks downloads until the install choices have loaded", async () => {
    let releaseModpacks!: (packs: unknown[]) => void;
    getModpacks.mockReturnValue(
      new Promise((resolve) => {
        releaseModpacks = resolve;
      }),
    );
    renderPage({ mod: mod({}) });

    const download = screen.getAllByRole("button", { name: /download/ })[0];
    expect(download).toBeDisabled();
    await userEvent.click(download);
    expect(installMod).not.toHaveBeenCalled();

    releaseModpacks([
      { name: "Pack", version: "1.20.1", modLoader: ModLoader.Fabric },
    ]);
    await waitFor(() => expect(download).not.toBeDisabled());
  });

  it("keeps the download disabled when a mod has no modpack to install into", async () => {
    getModpacks.mockResolvedValue([]);
    storeGet.mockResolvedValue(undefined);
    renderPage({ mod: mod({}) });

    await screen.findByText("jellysquid");
    const download = screen.getAllByRole("button", { name: /download/ })[0];
    expect(download).toBeDisabled();
    await userEvent.click(download);
    expect(installMod).not.toHaveBeenCalled();
  });

  it("ignores dependencies from a previously viewed mod", async () => {
    let releaseFirst!: (deps: IMod[]) => void;
    getModDependencies
      .mockReturnValueOnce(
        new Promise((resolve) => {
          releaseFirst = resolve;
        }),
      )
      .mockResolvedValue([mod({ id: "sodium-extra", name: "Sodium Extra" })]);

    const { rerender } = renderPage({ mod: mod({}) });
    rerender(
      <ContentContext.Provider
        value={{
          back,
          setSnackbar,
          changeContent: () => {},
          changePage: () => {},
          setSnackbarNoState: () => {},
        }}
      >
        <ModInstallPage mod={mod({ id: "iris", name: "Iris" })} />
      </ContentContext.Provider>,
    );
    expect(await screen.findByTestId("mod-card")).toHaveTextContent(
      "Sodium Extra",
    );

    // The first mod's response arriving late must not replace the current one.
    releaseFirst([mod({ id: "fabric-api", name: "Fabric API" })]);
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(screen.queryByText("Fabric API")).toBeNull();
    expect(screen.getByTestId("mod-card")).toHaveTextContent("Sodium Extra");
  });
});
