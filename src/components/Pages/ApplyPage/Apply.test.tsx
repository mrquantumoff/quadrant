/** @format */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { ModLoader } from "../../../intefaces";

const getVersions = vi.fn();
const getModpacks = vi.fn();
const getMinecraftFolder = vi.fn();

const storeGet = vi.fn();
const joinPath = vi.fn();
const watch = vi.fn();
const listen = vi.fn();

vi.mock("../../../tools", () => ({
  applyModpack: vi.fn(),
  createModpack: vi.fn(),
  deleteModpack: vi.fn(),
  exportModpack: vi.fn(),
  getMinecraftFolder: (...a: unknown[]) => getMinecraftFolder(...a),
  getModpacks: (...a: unknown[]) => getModpacks(...a),
  getVersions: (...a: unknown[]) => getVersions(...a),
  openModpacksFolder: vi.fn(),
  shareModpack: vi.fn(),
  syncModpack: vi.fn(),
  updateModpack: vi.fn(),
}));

vi.mock("../../../desktop", () => ({
  createDesktopStore: () => ({
    get: (...a: unknown[]) => storeGet(...a),
  }),
  joinPath: (...a: unknown[]) => joinPath(...a),
  listen: (...a: unknown[]) => listen(...a),
  watch: (...a: unknown[]) => watch(...a),
}));

// ModpackView is heavy and independently tested; stub it to a marker so the
// details navigation stays out of scope here.
vi.mock("../../shared/Pages/ModpackView", () => ({
  default: ({ name }: { name: string }) => (
    <div data-testid="modpack-view">{name}</div>
  ),
}));

import ApplyPage from "./Apply";

function pack(over: Record<string, unknown>) {
  return {
    name: "Pack",
    version: "1.20.1",
    modLoader: ModLoader.Fabric,
    isApplied: false,
    lastSynced: 0,
    mods: [],
    unknownMods: false,
    ...over,
  };
}

// Captures the callback each listen/watch registration is given so a test can
// drive the backend event by hand.
let watchCallback: (() => void) | undefined;
let shareCallback: ((event: unknown) => void) | undefined;

beforeEach(() => {
  vi.clearAllMocks();
  watchCallback = undefined;
  shareCallback = undefined;
  getVersions.mockResolvedValue([{ version: "1.20.1", versionType: "release" }]);
  getModpacks.mockResolvedValue([]);
  getMinecraftFolder.mockResolvedValue("/mc");
  storeGet.mockResolvedValue(true);
  joinPath.mockImplementation(async (...segments: string[]) => segments.join("/"));
  watch.mockImplementation(async (_path: string, cb: () => void) => {
    watchCallback = cb;
    return () => {};
  });
  listen.mockImplementation(async (event: string, cb: (e: unknown) => void) => {
    if (event === "quadrantShareSubmission") {
      shareCallback = cb;
    }
    return () => {};
  });
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("ApplyPage", () => {
  it("renders the modpacks returned by getModpacks", async () => {
    getModpacks.mockResolvedValue([
      pack({ name: "Alpha Pack" }),
      pack({ name: "Beta Pack" }),
    ]);

    render(<ApplyPage />);

    await waitFor(() =>
      expect(screen.getByText("Alpha Pack")).toBeInTheDocument(),
    );
    expect(screen.getByText("Beta Pack")).toBeInTheDocument();
  });

  it("registers the folder watch and the share-submission listener", async () => {
    render(<ApplyPage />);

    await waitFor(() => expect(watch).toHaveBeenCalledTimes(1));
    // The watch target is the joined Minecraft folder path, with a debounce.
    expect(watch).toHaveBeenCalledWith(
      "/mc",
      expect.any(Function),
      { delayMs: 50 },
    );
    expect(listen).toHaveBeenCalledWith(
      "quadrantShareSubmission",
      expect.any(Function),
    );
  });

  it("refetches modpacks when the filesystem watch fires", async () => {
    getModpacks.mockResolvedValue([pack({ name: "Original" })]);
    render(<ApplyPage />);

    await waitFor(() => expect(screen.getByText("Original")).toBeInTheDocument());
    await waitFor(() => expect(watchCallback).toBeTypeOf("function"));

    // The next fetch returns a different set; firing the watch must surface it.
    getModpacks.mockResolvedValue([pack({ name: "Refreshed" })]);
    watchCallback?.();

    await waitFor(() =>
      expect(screen.getByText("Refreshed")).toBeInTheDocument(),
    );
  });

  it("shows a snackbar-less share confirmation when the share event arrives", async () => {
    // The share listener drives a snackbar through context; with the default
    // (no-op) context we only assert the callback was wired and can be invoked
    // without throwing.
    render(<ApplyPage />);
    await waitFor(() => expect(shareCallback).toBeTypeOf("function"));
    expect(() =>
      shareCallback?.({ payload: { uses_left: 3 } }),
    ).not.toThrow();
  });
});

import { fireEvent } from "@testing-library/react";
import { ContentContext } from "../../../intefaces";
import { exportModpack } from "../../../tools";

describe("ApplyPage error handling and search", () => {
  it("surfaces an export failure through the snackbar", async () => {
    vi.mocked(exportModpack).mockRejectedValue("exportFailed");
    getModpacks.mockResolvedValue([pack({ name: "Alpha Pack" })]);
    const setSnackbar = vi.fn();
    render(
      <ContentContext.Provider
        value={{
          back: async () => {},
          changeContent: () => {},
          changePage: () => {},
          setSnackbar,
          setSnackbarNoState: () => {},
        }}
      >
        <ApplyPage />
      </ContentContext.Provider>,
    );
    await waitFor(() =>
      expect(screen.getByText("Alpha Pack")).toBeInTheDocument(),
    );

    fireEvent.click(screen.getByRole("button", { name: /export/i }));

    await waitFor(() => expect(setSnackbar).toHaveBeenCalledTimes(1));
    expect(setSnackbar.mock.calls[0][0]).toMatchObject({
      className: expect.stringContaining("bg-red-700"),
    });
  });

  it("ignores a slow response for a superseded search query", async () => {
    let resolveFirst!: (packs: ReturnType<typeof pack>[]) => void;
    // Mount fetches more than once, so key the responses on the query.
    getModpacks.mockImplementation(async (_hideFree: boolean, query: string) => {
      if (query === "a") {
        return new Promise((resolve) => {
          resolveFirst = resolve;
        });
      }
      if (query === "b") {
        return [pack({ name: "Beta Match" })];
      }
      return [pack({ name: "Initial" })];
    });
    render(<ApplyPage />);
    await waitFor(() => expect(screen.getByText("Initial")).toBeInTheDocument());

    const input = screen.getByPlaceholderText(/search/i);
    fireEvent.change(input, { target: { value: "a" } });
    await waitFor(() => expect(getModpacks).toHaveBeenCalledWith(true, "a"));
    fireEvent.change(input, { target: { value: "b" } });
    await waitFor(() =>
      expect(screen.getByText("Beta Match")).toBeInTheDocument(),
    );

    // The older request resolving last must not replace the newer results.
    resolveFirst([pack({ name: "Alpha Stale" })]);
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(screen.queryByText("Alpha Stale")).not.toBeInTheDocument();
    expect(screen.getByText("Beta Match")).toBeInTheDocument();
  });
});
