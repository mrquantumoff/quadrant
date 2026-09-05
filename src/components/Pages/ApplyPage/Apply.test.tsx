/** @format */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useContext, type ReactNode } from "react";
import { ContentContext, ModLoader } from "../../../intefaces";

const getVersions = vi.fn();
const getModpacks = vi.fn();
const getMinecraftFolder = vi.fn();
const getQuadrantShareModpack = vi.fn();

const storeGet = vi.fn();
const joinPath = vi.fn();
const watch = vi.fn();
const listen = vi.fn();
const readClipboardText = vi.fn();

vi.mock("../../../tools", () => ({
  applyModpack: vi.fn(),
  createModpack: vi.fn(),
  deleteModpack: vi.fn(),
  exportModpack: vi.fn(),
  getMinecraftFolder: (...a: unknown[]) => getMinecraftFolder(...a),
  getMod: vi.fn(),
  getModpacks: (...a: unknown[]) => getModpacks(...a),
  getQuadrantShareModpack: (...a: unknown[]) => getQuadrantShareModpack(...a),
  getVersions: (...a: unknown[]) => getVersions(...a),
  installModpack: vi.fn(),
  openModpacksFolder: vi.fn(),
  shareModpack: vi.fn(),
  syncModpack: vi.fn(),
  updateModpack: vi.fn(),
}));

vi.mock("../../../desktop", () => ({
  createDesktopStore: () => ({
    get: (...a: unknown[]) => storeGet(...a),
  }),
  invoke: vi.fn(),
  joinPath: (...a: unknown[]) => joinPath(...a),
  listen: (...a: unknown[]) => listen(...a),
  readClipboardText: (...a: unknown[]) => readClipboardText(...a),
  watch: (...a: unknown[]) => watch(...a),
}));

// ModpackView is heavy and independently tested; stub it to a marker so the
// details navigation stays out of scope here.
vi.mock("../../shared/Pages/ModpackView", () => ({
  default: ({ name }: { name: string }) => (
    <div data-testid="modpack-view">{name}</div>
  ),
}));

// CloudModpackSection fetches account info and synced modpacks of its own; stub
// it to a marker so only the local list and share-code flow are in scope here.
vi.mock("./CloudModpackSection", () => ({
  default: ({ searchQuery }: { searchQuery: string }) => (
    <div data-testid="cloud-modpack-section">{searchQuery}</div>
  ),
}));

import ApplyPage from "./Apply";

const changeContent = vi.fn();
const setSnackbar = vi.fn();

// Spreading the inherited context keeps this provider valid as ContentContext
// grows; only the two members these tests observe are replaced with spies.
function SpiedContent({ children }: { children: ReactNode }) {
  const inherited = useContext(ContentContext);
  return (
    <ContentContext.Provider
      value={{ ...inherited, changeContent, setSnackbar }}
    >
      {children}
    </ContentContext.Provider>
  );
}

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
  getQuadrantShareModpack.mockResolvedValue({
    name: "Shared Pack",
    mods: [],
    modLoader: ModLoader.Fabric,
    version: "1.20.1",
  });
  readClipboardText.mockResolvedValue("1234567");
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

  it("offers the Quadrant Share prompt only for a share code", async () => {
    render(<ApplyPage />);
    const input = screen.getByRole("textbox");

    await userEvent.type(input, "alpha");
    expect(
      screen.queryByRole("button", { name: /^download$/i }),
    ).not.toBeInTheDocument();

    await userEvent.clear(input);
    await userEvent.type(input, "1234567");
    expect(
      screen.getByRole("button", { name: /^download$/i }),
    ).toBeInTheDocument();
  });

  it("resolves the typed share code when the prompt is confirmed", async () => {
    render(<ApplyPage />);

    await userEvent.type(screen.getByRole("textbox"), "1234567");
    await userEvent.click(screen.getByRole("button", { name: /^download$/i }));

    await waitFor(() =>
      expect(getQuadrantShareModpack).toHaveBeenCalledWith("1234567"),
    );
  });

  it("shows the error snackbar and stays put when the lookup fails", async () => {
    getQuadrantShareModpack.mockRejectedValue(new Error("gone"));
    render(
      <SpiedContent>
        <ApplyPage />
      </SpiedContent>,
    );

    await userEvent.type(screen.getByRole("textbox"), "1234567");
    await userEvent.click(screen.getByRole("button", { name: /^download$/i }));

    await waitFor(() =>
      expect(setSnackbar).toHaveBeenCalledWith(
        expect.objectContaining({ className: "bg-red-700 rounded-4xl" }),
      ),
    );
    expect(changeContent).not.toHaveBeenCalled();
  });

  it("pastes the clipboard into the search query", async () => {
    readClipboardText.mockResolvedValue("  1234567  ");
    render(<ApplyPage />);

    await userEvent.click(screen.getByRole("button", { name: /^paste$/i }));

    await waitFor(() =>
      expect(screen.getByRole("textbox")).toHaveValue("1234567"),
    );
    // Asserts the ref was updated too: updateModpacks reads it, not the state.
    await waitFor(() =>
      expect(getModpacks).toHaveBeenCalledWith(true, "1234567"),
    );
  });
});
