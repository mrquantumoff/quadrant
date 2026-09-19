/** @format */

import { beforeEach, describe, expect, it, vi } from "vitest";
import { act, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useContext, type ReactNode } from "react";
import { ContentContext, ModType } from "../../../intefaces";

const getInstalledContent = vi.fn();
const openContentFolder = vi.fn();
const copyContent = vi.fn();
const deleteContent = vi.fn();

vi.mock("../../../tools", () => ({
  getInstalledContent: (...a: unknown[]) => getInstalledContent(...a),
  openContentFolder: (...a: unknown[]) => openContentFolder(...a),
  copyContent: (...a: unknown[]) => copyContent(...a),
  deleteContent: (...a: unknown[]) => deleteContent(...a),
}));

import InstalledContentPage from "./InstalledContentPage";

const setSnackbar = vi.fn();

// Spreading the inherited context keeps this provider valid as ContentContext
// grows; only the member these tests observe is replaced with a spy.
function SpiedContent({ children }: { children: ReactNode }) {
  const inherited = useContext(ContentContext);
  return (
    <ContentContext.Provider value={{ ...inherited, setSnackbar }}>
      {children}
    </ContentContext.Provider>
  );
}

function file(over: Record<string, unknown>) {
  return {
    fileName: "pack.zip",
    size: 1536,
    modified: 1700000000000,
    isDirectory: false,
    ...over,
  };
}

/** Builds a location the way the host reports one: packs first, then shaders. */
function location(
  over: Record<string, unknown> & {
    resourcePacks?: ReturnType<typeof file>[];
    shaderPacks?: ReturnType<typeof file>[];
  },
) {
  const { resourcePacks = [], shaderPacks = [], ...rest } = over;
  return {
    id: "minecraft",
    kind: "minecraft",
    name: "",
    path: "/home/me/.minecraft",
    sections: [
      { modType: ModType.ResourcePack, files: resourcePacks },
      { modType: ModType.ShaderPack, files: shaderPacks },
    ],
    ...rest,
  };
}

/** A promise whose resolution is controlled by the test. */
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}

function renderPage() {
  return render(
    <SpiedContent>
      <InstalledContentPage />
    </SpiedContent>,
  );
}

/** Sections start folded, so most assertions need one opened first. */
async function openSection(title: string, index = 0) {
  await userEvent.click((await screen.findAllByText(title))[index]);
}

const refreshButton = () => screen.getByRole("button", { name: "Refresh" });

beforeEach(() => {
  vi.clearAllMocks();
  getInstalledContent.mockResolvedValue([]);
  openContentFolder.mockResolvedValue(undefined);
  copyContent.mockResolvedValue(1);
  deleteContent.mockResolvedValue(1);
});

describe("InstalledContentPage", () => {
  it("shows the Minecraft folder under a localized name with its path", async () => {
    getInstalledContent.mockResolvedValue([
      location({ resourcePacks: [file({ fileName: "Faithful.zip" })] }),
    ]);
    renderPage();

    expect(await screen.findByText("Minecraft folder")).toBeInTheDocument();
    expect(screen.getByText("/home/me/.minecraft")).toBeInTheDocument();
    await openSection("Resource Packs");
    expect(screen.getByText("Faithful.zip")).toBeInTheDocument();
  });

  it("names a Prism instance and tags it as Prism Launcher", async () => {
    getInstalledContent.mockResolvedValue([
      location({}),
      location({
        id: "prism:1",
        kind: "prism",
        name: "Survival",
        path: "/home/me/prism/Survival/.minecraft",
        shaderPacks: [file({ fileName: "BSL.zip" })],
      }),
    ]);
    renderPage();

    expect(await screen.findByText("Survival")).toBeInTheDocument();
    expect(screen.getByText("Prism Launcher")).toBeInTheDocument();
    await openSection("Shaders", 1);
    expect(screen.getByText("BSL.zip")).toBeInTheDocument();
  });

  it("tells the user when a section holds nothing", async () => {
    getInstalledContent.mockResolvedValue([location({})]);
    renderPage();

    await openSection("Resource Packs");
    await openSection("Shaders");
    expect(screen.getAllByText("Nothing installed")).toHaveLength(2);
  });

  it("describes a file by size and date, and a folder by its kind", async () => {
    getInstalledContent.mockResolvedValue([
      location({
        resourcePacks: [
          file({ fileName: "Faithful.zip" }),
          file({ fileName: "Unzipped", size: 0, isDirectory: true }),
          file({ fileName: "NoDate.zip", size: 5242880, modified: 0 }),
        ],
      }),
    ]);
    renderPage();
    await openSection("Resource Packs");

    // The date half is matched loosely: it is rendered in the machine's zone.
    expect(
      screen.getByText(/^1\.5kB · \d\d\/\d\d\/\d\d, \d\d:\d\d$/),
    ).toBeInTheDocument();
    expect(
      screen.getByText(/^Folder · \d\d\/\d\d\/\d\d, \d\d:\d\d$/),
    ).toBeInTheDocument();
    expect(screen.getByText("5MB")).toBeInTheDocument();
  });

  it("keeps the file list folded away until the section is opened", async () => {
    getInstalledContent.mockResolvedValue([
      location({ resourcePacks: [file({ fileName: "Faithful.zip" })] }),
    ]);
    renderPage();

    // The count keeps the folded header informative.
    expect(await screen.findByText("Resource Packs")).toBeInTheDocument();
    expect(screen.getByText("1")).toBeInTheDocument();
    expect(screen.queryByText("Faithful.zip")).toBeNull();

    await openSection("Resource Packs");
    expect(screen.getByText("Faithful.zip")).toBeInTheDocument();
  });

  it("opens the folder matching the section that was clicked, while folded", async () => {
    getInstalledContent.mockResolvedValue([
      location({}),
      location({
        id: "prism:1",
        kind: "prism",
        name: "Survival",
        shaderPacks: [file({ fileName: "BSL.zip" })],
      }),
    ]);
    renderPage();

    await userEvent.click(
      await screen.findByRole("button", {
        name: "Open the Resource Packs folder of Minecraft folder",
      }),
    );
    expect(openContentFolder).toHaveBeenCalledWith(
      "minecraft",
      ModType.ResourcePack,
    );

    await userEvent.click(
      screen.getByRole("button", {
        name: "Open the Shaders folder of Survival",
      }),
    );
    expect(openContentFolder).toHaveBeenCalledWith(
      "prism:1",
      ModType.ShaderPack,
    );
    expect(screen.queryByText("BSL.zip")).toBeNull();
  });

  it("refetches when refresh is pressed", async () => {
    getInstalledContent.mockResolvedValue([
      location({ resourcePacks: [file({ fileName: "Before.zip" })] }),
    ]);
    renderPage();
    await openSection("Resource Packs");
    expect(screen.getByText("Before.zip")).toBeInTheDocument();

    getInstalledContent.mockResolvedValue([
      location({ resourcePacks: [file({ fileName: "After.zip" })] }),
    ]);
    await userEvent.click(refreshButton());

    await openSection("Resource Packs");
    expect(screen.getByText("After.zip")).toBeInTheDocument();
    expect(getInstalledContent).toHaveBeenCalledTimes(2);
  });

  it("reports a failed load and leaves the refresh button working", async () => {
    getInstalledContent.mockRejectedValueOnce(new Error("boom"));
    renderPage();

    await waitFor(() => {
      expect(setSnackbar).toHaveBeenCalled();
    });
    expect(screen.queryByText("Resource Packs")).not.toBeInTheDocument();

    getInstalledContent.mockResolvedValue([
      location({ resourcePacks: [file({ fileName: "Retried.zip" })] }),
    ]);
    await userEvent.click(refreshButton());

    await openSection("Resource Packs");
    expect(screen.getByText("Retried.zip")).toBeInTheDocument();
  });

  it("starts a later location collapsed when it holds nothing", async () => {
    getInstalledContent.mockResolvedValue([
      location({ resourcePacks: [file({ fileName: "Faithful.zip" })] }),
      location({ id: "prism:1", kind: "prism", name: "Empty" }),
      location({
        id: "prism:2",
        kind: "prism",
        name: "Modded",
        shaderPacks: [file({ fileName: "BSL.zip" })],
      }),
    ]);
    renderPage();

    // The first location is never collapsible, the third opens because it has
    // content, so only the empty second one withholds its sections.
    expect(await screen.findByText("Empty")).toBeInTheDocument();
    expect(screen.getAllByText("Resource Packs")).toHaveLength(2);
    expect(screen.getAllByText("Shaders")).toHaveLength(2);

    await userEvent.click(screen.getByText("Empty"));
    expect(screen.getAllByText("Resource Packs")).toHaveLength(3);
  });
});

describe("InstalledContentPage — copying between locations", () => {
  const minecraft = location({
    resourcePacks: [
      file({ fileName: "Faithful.zip" }),
      file({ fileName: "Alpha.zip" }),
      file({ fileName: "Beta.zip" }),
    ],
  });
  const survival = location({
    id: "prism:1",
    kind: "prism",
    name: "Survival",
    path: "/home/me/prism/Survival/.minecraft",
    resourcePacks: [file({ fileName: "Faithful.zip" })],
  });

  beforeEach(() => {
    getInstalledContent.mockResolvedValue([minecraft, survival]);
  });

  it("offers no copy controls when there is nowhere else to copy to", async () => {
    getInstalledContent.mockResolvedValue([minecraft]);
    renderPage();
    await openSection("Resource Packs");

    expect(screen.queryByRole("button", { name: /Copy all/ })).toBeNull();
    expect(
      screen.queryByRole("button", {
        name: "Copy Faithful.zip somewhere else",
      }),
    ).toBeNull();
  });

  it("lists the other locations for a file and checks off the ones that have it", async () => {
    renderPage();
    await openSection("Resource Packs");

    await userEvent.click(
      screen.getByRole("button", { name: "Copy Faithful.zip somewhere else" }),
    );
    // Survival already holds this one, so there is nothing to do there.
    expect(
      await screen.findByRole("menuitem", { name: "Survival" }),
    ).toBeDisabled();
    expect(
      screen.queryByRole("menuitem", { name: "Minecraft folder" }),
    ).toBeNull();
  });

  it("copies one file to the chosen location and reloads the listing", async () => {
    renderPage();
    await openSection("Resource Packs");

    await userEvent.click(
      screen.getByRole("button", { name: "Copy Alpha.zip somewhere else" }),
    );
    await userEvent.click(
      await screen.findByRole("menuitem", { name: "Survival" }),
    );

    await waitFor(() =>
      expect(copyContent).toHaveBeenCalledWith(
        "minecraft",
        "prism:1",
        ModType.ResourcePack,
        ["Alpha.zip"],
      ),
    );
    await waitFor(() => expect(getInstalledContent).toHaveBeenCalledTimes(2));
    expect(setSnackbar).toHaveBeenCalledWith(
      expect.objectContaining({ className: "bg-emerald-600 rounded-4xl" }),
    );
  });

  it("copies only what the destination is missing, and says how many", async () => {
    copyContent.mockResolvedValue(2);
    renderPage();
    await openSection("Resource Packs");

    await userEvent.click(
      screen.getByRole("button", {
        name: "Copy all Resource Packs of Minecraft folder somewhere else",
      }),
    );
    await userEvent.click(
      await screen.findByRole("menuitem", { name: "Survival · 2 new" }),
    );

    await waitFor(() =>
      expect(copyContent).toHaveBeenCalledWith(
        "minecraft",
        "prism:1",
        ModType.ResourcePack,
        ["Alpha.zip", "Beta.zip"],
      ),
    );
    render(setSnackbar.mock.calls[0][0].message);
    expect(screen.getByText("Copied 2 packs to Survival")).toBeInTheDocument();
  });

  it("offers copy all while the section is folded", async () => {
    renderPage();

    await userEvent.click(
      await screen.findByRole("button", {
        name: "Copy all Resource Packs of Minecraft folder somewhere else",
      }),
    );
    expect(
      await screen.findByRole("menuitem", { name: "Survival · 2 new" }),
    ).toBeInTheDocument();
    expect(screen.queryByText("Alpha.zip")).toBeNull();
  });

  it("offers nothing to copy when the destination is already complete", async () => {
    getInstalledContent.mockResolvedValue([
      location({ resourcePacks: [file({ fileName: "Faithful.zip" })] }),
      survival,
    ]);
    renderPage();

    await userEvent.click(
      await screen.findByRole("button", {
        name: "Copy all Resource Packs of Minecraft folder somewhere else",
      }),
    );
    expect(
      await screen.findByRole("menuitem", { name: "Survival · 0 new" }),
    ).toBeDisabled();
  });

  it("reports a copy that failed", async () => {
    copyContent.mockRejectedValue("errorContentMissing");
    renderPage();
    await openSection("Resource Packs");

    await userEvent.click(
      screen.getByRole("button", { name: "Copy Alpha.zip somewhere else" }),
    );
    await userEvent.click(
      await screen.findByRole("menuitem", { name: "Survival" }),
    );

    await waitFor(() =>
      expect(setSnackbar).toHaveBeenCalledWith(
        expect.objectContaining({ className: "bg-red-700" }),
      ),
    );
    expect(getInstalledContent).toHaveBeenCalledTimes(1);
  });

  it("keeps the opened section on screen while the reload runs", async () => {
    getInstalledContent
      .mockResolvedValueOnce([minecraft, survival])
      .mockReturnValueOnce(new Promise(() => {}));
    renderPage();
    await openSection("Resource Packs");

    await userEvent.click(
      screen.getByRole("button", { name: "Copy Alpha.zip somewhere else" }),
    );
    await userEvent.click(
      await screen.findByRole("menuitem", { name: "Survival" }),
    );

    await waitFor(() => expect(getInstalledContent).toHaveBeenCalledTimes(2));
    // The listing is never cleared, so the section the user opened survives.
    expect(screen.getByText("Alpha.zip")).toBeInTheDocument();
  });
});

describe("InstalledContentPage — deleting a pack", () => {
  const minecraft = location({
    resourcePacks: [
      file({ fileName: "Faithful.zip" }),
      file({ fileName: "Alpha.zip" }),
    ],
  });

  beforeEach(() => {
    getInstalledContent.mockResolvedValue([minecraft]);
  });

  it("arms on the first click and deletes on the second", async () => {
    renderPage();
    await openSection("Resource Packs");

    await userEvent.click(
      screen.getByRole("button", { name: "Delete Alpha.zip" }),
    );
    expect(deleteContent).not.toHaveBeenCalled();

    await userEvent.click(
      screen.getByRole("button", { name: "Confirm deleting Alpha.zip" }),
    );
    await waitFor(() =>
      expect(deleteContent).toHaveBeenCalledWith(
        "minecraft",
        ModType.ResourcePack,
        ["Alpha.zip"],
      ),
    );
    await waitFor(() => expect(getInstalledContent).toHaveBeenCalledTimes(2));
    expect(setSnackbar).toHaveBeenCalledWith(
      expect.objectContaining({ className: "bg-emerald-600 rounded-4xl" }),
    );
  });

  it("arms one row at a time", async () => {
    renderPage();
    await openSection("Resource Packs");

    await userEvent.click(
      screen.getByRole("button", { name: "Delete Alpha.zip" }),
    );
    await userEvent.click(
      screen.getByRole("button", { name: "Delete Faithful.zip" }),
    );

    expect(
      screen.getByRole("button", { name: "Confirm deleting Faithful.zip" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Delete Alpha.zip" }),
    ).toBeInTheDocument();
    expect(deleteContent).not.toHaveBeenCalled();
  });

  it("forgets an armed delete that is left alone", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime });
    try {
      renderPage();
      await user.click((await screen.findAllByText("Resource Packs"))[0]);
      await user.click(
        screen.getByRole("button", { name: "Delete Alpha.zip" }),
      );
      expect(
        screen.getByRole("button", { name: "Confirm deleting Alpha.zip" }),
      ).toBeInTheDocument();

      act(() => {
        vi.advanceTimersByTime(4000);
      });
      expect(
        screen.getByRole("button", { name: "Delete Alpha.zip" }),
      ).toBeInTheDocument();
    } finally {
      vi.useRealTimers();
    }
  });

  it("reports a delete that failed", async () => {
    deleteContent.mockRejectedValue("errorContentMissing");
    renderPage();
    await openSection("Resource Packs");

    await userEvent.click(
      screen.getByRole("button", { name: "Delete Alpha.zip" }),
    );
    await userEvent.click(
      screen.getByRole("button", { name: "Confirm deleting Alpha.zip" }),
    );

    await waitFor(() =>
      expect(setSnackbar).toHaveBeenCalledWith(
        expect.objectContaining({ className: "bg-red-700" }),
      ),
    );
    expect(getInstalledContent).toHaveBeenCalledTimes(1);
  });
});

describe("InstalledContentPage — acting on several packs", () => {
  const minecraft = location({
    resourcePacks: [
      file({ fileName: "Faithful.zip" }),
      file({ fileName: "Alpha.zip" }),
      file({ fileName: "Beta.zip" }),
    ],
    shaderPacks: [file({ fileName: "BSL.zip" })],
  });
  const survival = location({
    id: "prism:1",
    kind: "prism",
    name: "Survival",
    path: "/home/me/prism/Survival/.minecraft",
    resourcePacks: [file({ fileName: "Faithful.zip" })],
  });

  beforeEach(() => {
    getInstalledContent.mockResolvedValue([minecraft, survival]);
  });

  async function tick(name: string) {
    await userEvent.click(screen.getByRole("checkbox", { name }));
  }

  const selectAll = (section: string, name: string) =>
    screen.getByRole("button", { name: `Select all ${section} of ${name}` });

  it("keeps the selection bar away until something is ticked", async () => {
    renderPage();
    await openSection("Resource Packs");

    expect(screen.queryByText(/selected/)).toBeNull();
    expect(
      screen.queryByRole("button", { name: "Delete selected" }),
    ).toBeNull();
    // "Select all" belongs to the section, so it is there before any tick.
    expect(selectAll("Resource Packs", "Minecraft folder")).toBeInTheDocument();

    await tick("Alpha.zip");
    expect(screen.getByText("1 pack selected")).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Delete selected" }),
    ).toBeInTheDocument();
  });

  it("counts what is ticked, selects a section, and clears", async () => {
    renderPage();
    await openSection("Resource Packs");

    await tick("Alpha.zip");
    await tick("Beta.zip");
    expect(screen.getByText("2 packs selected")).toBeInTheDocument();

    await userEvent.click(selectAll("Resource Packs", "Minecraft folder"));
    expect(screen.getByText("3 packs selected")).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: "Clear" }));
    expect(screen.queryByText(/selected/)).toBeNull();
  });

  it("keeps a tick made in another section", async () => {
    renderPage();
    await openSection("Resource Packs");
    await openSection("Shaders");

    await tick("Alpha.zip");
    await tick("BSL.zip");

    expect(screen.getByText("2 packs selected")).toBeInTheDocument();
    expect(screen.getByRole("checkbox", { name: "Alpha.zip" })).toBeChecked();
    expect(screen.getByRole("checkbox", { name: "BSL.zip" })).toBeChecked();
  });

  it("keeps a tick made in another location", async () => {
    renderPage();
    await openSection("Resource Packs");
    await openSection("Resource Packs", 1);

    await tick("Alpha.zip");
    // Survival's copy of Faithful.zip is a different row of the same name.
    await userEvent.click(
      screen.getAllByRole("checkbox", { name: "Faithful.zip" })[1],
    );

    expect(screen.getByText("2 packs selected")).toBeInTheDocument();
  });

  it("adds only the files of the section whose Select all was pressed", async () => {
    renderPage();
    await openSection("Resource Packs");
    await openSection("Shaders");

    await tick("BSL.zip");
    await userEvent.click(selectAll("Resource Packs", "Minecraft folder"));

    expect(screen.getByText("4 packs selected")).toBeInTheDocument();
    expect(screen.getByRole("checkbox", { name: "BSL.zip" })).toBeChecked();
  });

  it("deletes everything ticked in one call, after confirming", async () => {
    deleteContent.mockResolvedValue(2);
    getInstalledContent
      .mockResolvedValueOnce([minecraft, survival])
      .mockResolvedValue([
        location({
          resourcePacks: [file({ fileName: "Faithful.zip" })],
          shaderPacks: [file({ fileName: "BSL.zip" })],
        }),
        survival,
      ]);
    renderPage();
    await openSection("Resource Packs");

    await tick("Alpha.zip");
    await tick("Beta.zip");
    await userEvent.click(
      screen.getByRole("button", { name: "Delete selected" }),
    );
    expect(deleteContent).not.toHaveBeenCalled();

    await userEvent.click(screen.getByRole("button", { name: "Delete 2?" }));
    await waitFor(() =>
      expect(deleteContent).toHaveBeenCalledWith(
        "minecraft",
        ModType.ResourcePack,
        ["Alpha.zip", "Beta.zip"],
      ),
    );
    expect(deleteContent).toHaveBeenCalledTimes(1);
    // The reload no longer reports them, so the selection empties itself.
    await waitFor(() => expect(screen.queryByText(/selected/)).toBeNull());
    render(setSnackbar.mock.calls[0][0].message);
    expect(screen.getByText("Deleted 2 packs")).toBeInTheDocument();
  });

  it("issues one delete per section, and counts them together", async () => {
    deleteContent.mockResolvedValue(1);
    getInstalledContent
      .mockResolvedValueOnce([minecraft, survival])
      .mockResolvedValue([location({}), survival]);
    renderPage();
    await openSection("Resource Packs");
    await openSection("Shaders");

    await tick("Alpha.zip");
    await tick("BSL.zip");
    await userEvent.click(
      screen.getByRole("button", { name: "Delete selected" }),
    );
    await userEvent.click(screen.getByRole("button", { name: "Delete 2?" }));

    await waitFor(() => expect(deleteContent).toHaveBeenCalledTimes(2));
    expect(deleteContent).toHaveBeenNthCalledWith(
      1,
      "minecraft",
      ModType.ResourcePack,
      ["Alpha.zip"],
    );
    expect(deleteContent).toHaveBeenNthCalledWith(
      2,
      "minecraft",
      ModType.ShaderPack,
      ["BSL.zip"],
    );
    render(setSnackbar.mock.calls[0][0].message);
    expect(screen.getByText("Deleted 2 packs")).toBeInTheDocument();
  });

  it("issues one delete per location a tick was made in", async () => {
    getInstalledContent.mockResolvedValue([minecraft, survival]);
    renderPage();
    await openSection("Resource Packs");
    await openSection("Resource Packs", 1);

    await tick("Alpha.zip");
    await userEvent.click(
      screen.getAllByRole("checkbox", { name: "Faithful.zip" })[1],
    );
    await userEvent.click(
      screen.getByRole("button", { name: "Delete selected" }),
    );
    await userEvent.click(screen.getByRole("button", { name: "Delete 2?" }));

    await waitFor(() => expect(deleteContent).toHaveBeenCalledTimes(2));
    expect(deleteContent).toHaveBeenNthCalledWith(
      1,
      "minecraft",
      ModType.ResourcePack,
      ["Alpha.zip"],
    );
    expect(deleteContent).toHaveBeenNthCalledWith(
      2,
      "prism:1",
      ModType.ResourcePack,
      ["Faithful.zip"],
    );
  });

  it("stops at a failed group, reports it, and still reloads", async () => {
    deleteContent
      .mockResolvedValueOnce(1)
      .mockRejectedValueOnce("errorContentMissing");
    renderPage();
    await openSection("Resource Packs");
    await openSection("Shaders");

    await tick("Alpha.zip");
    await tick("BSL.zip");
    await userEvent.click(
      screen.getByRole("button", { name: "Delete selected" }),
    );
    await userEvent.click(screen.getByRole("button", { name: "Delete 2?" }));

    await waitFor(() =>
      expect(setSnackbar).toHaveBeenCalledWith(
        expect.objectContaining({ className: "bg-red-700" }),
      ),
    );
    expect(deleteContent).toHaveBeenCalledTimes(2);
    // The first group is already gone, so the listing must be read again.
    await waitFor(() => expect(getInstalledContent).toHaveBeenCalledTimes(2));
  });

  it("copies only what the destination misses out of the ticked files", async () => {
    copyContent.mockResolvedValue(1);
    renderPage();
    await openSection("Resource Packs");

    await tick("Faithful.zip");
    await tick("Alpha.zip");
    await userEvent.click(
      screen.getByRole("button", {
        name: "Copy the selected packs somewhere else",
      }),
    );
    await userEvent.click(
      await screen.findByRole("menuitem", { name: "Survival · 1 new" }),
    );

    await waitFor(() =>
      expect(copyContent).toHaveBeenCalledWith(
        "minecraft",
        "prism:1",
        ModType.ResourcePack,
        ["Alpha.zip"],
      ),
    );
    expect(copyContent).toHaveBeenCalledTimes(1);
  });

  it("never copies a destination's own ticked files back to it", async () => {
    copyContent.mockResolvedValue(1);
    renderPage();
    await openSection("Resource Packs");
    await openSection("Resource Packs", 1);

    await tick("Alpha.zip");
    await userEvent.click(
      screen.getAllByRole("checkbox", { name: "Faithful.zip" })[1],
    );
    await userEvent.click(
      screen.getByRole("button", {
        name: "Copy the selected packs somewhere else",
      }),
    );

    // Only Alpha.zip is left to send to Survival; its own pack never travels.
    await userEvent.click(
      await screen.findByRole("menuitem", { name: "Survival · 1 new" }),
    );
    await waitFor(() =>
      expect(copyContent).toHaveBeenCalledWith(
        "minecraft",
        "prism:1",
        ModType.ResourcePack,
        ["Alpha.zip"],
      ),
    );
    expect(copyContent).toHaveBeenCalledTimes(1);
  });

  it("copies a selection spanning two sections, one call each", async () => {
    copyContent.mockResolvedValue(1);
    getInstalledContent.mockResolvedValue([
      minecraft,
      location({ id: "prism:2", kind: "prism", name: "Modded" }),
    ]);
    renderPage();
    await openSection("Resource Packs");
    await openSection("Shaders");

    await tick("Alpha.zip");
    await tick("BSL.zip");
    await userEvent.click(
      screen.getByRole("button", {
        name: "Copy the selected packs somewhere else",
      }),
    );
    await userEvent.click(
      await screen.findByRole("menuitem", { name: "Modded · 2 new" }),
    );

    await waitFor(() => expect(copyContent).toHaveBeenCalledTimes(2));
    expect(copyContent).toHaveBeenNthCalledWith(
      1,
      "minecraft",
      "prism:2",
      ModType.ResourcePack,
      ["Alpha.zip"],
    );
    expect(copyContent).toHaveBeenNthCalledWith(
      2,
      "minecraft",
      "prism:2",
      ModType.ShaderPack,
      ["BSL.zip"],
    );
  });

  it("forgets a ticked file the reload no longer reports", async () => {
    getInstalledContent
      .mockResolvedValueOnce([minecraft, survival])
      .mockResolvedValue([
        location({
          resourcePacks: [
            file({ fileName: "Faithful.zip" }),
            file({ fileName: "Beta.zip" }),
          ],
          shaderPacks: [file({ fileName: "BSL.zip" })],
        }),
        survival,
      ]);
    renderPage();
    await openSection("Resource Packs");

    await tick("Alpha.zip");
    await tick("Beta.zip");
    await userEvent.click(
      screen.getByRole("button", { name: "Delete Alpha.zip" }),
    );
    await userEvent.click(
      screen.getByRole("button", { name: "Confirm deleting Alpha.zip" }),
    );

    await waitFor(() =>
      expect(screen.getByText("1 pack selected")).toBeInTheDocument(),
    );
    expect(screen.getByRole("checkbox", { name: "Beta.zip" })).toBeChecked();
  });
});

describe("InstalledContentPage — refreshing while an action runs", () => {
  const minecraft = location({
    resourcePacks: [
      file({ fileName: "Faithful.zip" }),
      file({ fileName: "Alpha.zip" }),
    ],
  });
  const survival = location({
    id: "prism:1",
    kind: "prism",
    name: "Survival",
    path: "/home/me/prism/Survival/.minecraft",
  });

  it("locks out a manual refresh until the copy is done", async () => {
    getInstalledContent.mockResolvedValue([minecraft, survival]);
    const copying = deferred<number>();
    copyContent.mockReturnValue(copying.promise);
    renderPage();
    await openSection("Resource Packs");

    await userEvent.click(
      screen.getByRole("button", { name: "Copy Alpha.zip somewhere else" }),
    );
    await userEvent.click(
      await screen.findByRole("menuitem", { name: "Survival" }),
    );

    // A reload here would swap the cards for the spinner and race the reload
    // the copy does itself.
    await waitFor(() => expect(refreshButton()).toBeDisabled());

    await act(async () => copying.resolve(1));
    await waitFor(() => expect(refreshButton()).toBeEnabled());
  });

  it("keeps the newest listing when an earlier load answers late", async () => {
    const stale = deferred<unknown[]>();
    const fresh = deferred<unknown[]>();
    getInstalledContent
      .mockResolvedValueOnce([minecraft])
      .mockReturnValueOnce(stale.promise)
      .mockReturnValueOnce(fresh.promise);
    renderPage();
    await screen.findByText("Minecraft folder");

    await userEvent.click(refreshButton());
    await userEvent.click(refreshButton());
    expect(getInstalledContent).toHaveBeenCalledTimes(3);

    await act(async () =>
      fresh.resolve([
        location({ id: "prism:2", kind: "prism", name: "Fresh" }),
      ]),
    );
    expect(await screen.findByText("Fresh")).toBeInTheDocument();

    await act(async () =>
      stale.resolve([
        location({ id: "prism:3", kind: "prism", name: "Stale" }),
      ]),
    );
    expect(screen.getByText("Fresh")).toBeInTheDocument();
    expect(screen.queryByText("Stale")).toBeNull();
  });
});
