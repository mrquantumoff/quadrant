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
const getAccountInfo = vi.fn();
const getSyncedModpacks = vi.fn();
const syncModpack = vi.fn();
const installModpack = vi.fn();
const invoke = vi.fn();

const storeGet = vi.fn();
const joinPath = vi.fn();
const watch = vi.fn();
const listen = vi.fn();

vi.mock("../../../tools", () => ({
  applyModpack: vi.fn(),
  createModpack: vi.fn(),
  deleteModpack: vi.fn(),
  exportModpack: vi.fn(),
  getAccountInfo: (...a: unknown[]) => getAccountInfo(...a),
  getSyncedModpacks: (...a: unknown[]) => getSyncedModpacks(...a),
  inviteMember: vi.fn(),
  kickMember: vi.fn(),
  getMinecraftFolder: (...a: unknown[]) => getMinecraftFolder(...a),
  getMod: vi.fn(),
  getModpacks: (...a: unknown[]) => getModpacks(...a),
  getQuadrantShareModpack: (...a: unknown[]) => getQuadrantShareModpack(...a),
  getVersions: (...a: unknown[]) => getVersions(...a),
  installModpack: (...a: unknown[]) => installModpack(...a),
  openModpacksFolder: vi.fn(),
  shareModpack: vi.fn(),
  shareModpackRaw: vi.fn(),
  syncModpack: (...a: unknown[]) => syncModpack(...a),
  updateModpack: vi.fn(),
}));

vi.mock("../../../desktop", () => ({
  createDesktopStore: () => ({
    get: (...a: unknown[]) => storeGet(...a),
  }),
  invoke: (...a: unknown[]) => invoke(...a),
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

// SharedModpackView fetches every mod of the pack; stub it to a marker so the
// details navigation only has to prove it was pushed.
vi.mock("./SharedModpackView", () => ({
  default: ({ modpack }: { modpack: { name: string } }) => (
    <div data-testid="shared-modpack-view">{modpack.name}</div>
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

function cloudPack(over: Record<string, unknown>) {
  return {
    name: "Pack",
    modpack_id: "id",
    minecraft_version: "1.20.1",
    mod_loader: ModLoader.Fabric,
    mods: "[]",
    owners: [{ username: "me", admin: true }],
    last_synced: 1,
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
  getVersions.mockResolvedValue([
    { version: "1.20.1", versionType: "release" },
  ]);
  getModpacks.mockResolvedValue([]);
  getMinecraftFolder.mockResolvedValue("/mc");
  // Signed out by default: the cloud list stays empty.
  getAccountInfo.mockRejectedValue(new Error("signed out"));
  getSyncedModpacks.mockResolvedValue([]);
  getQuadrantShareModpack.mockResolvedValue({
    name: "Shared Pack",
    mods: [],
    modLoader: ModLoader.Fabric,
    version: "1.20.1",
  });
  storeGet.mockResolvedValue(true);
  joinPath.mockImplementation(async (...segments: string[]) =>
    segments.join("/"),
  );
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

    await waitFor(() => expect(watch).toHaveBeenCalledTimes(2));
    // The Minecraft folder is watched flat (the mods link flips on apply) and
    // the modpacks tree recursively, both debounced.
    expect(watch).toHaveBeenCalledWith("/mc", expect.any(Function), {
      delayMs: 50,
    });
    expect(watch).toHaveBeenCalledWith("/mc/modpacks", expect.any(Function), {
      delayMs: 50,
      recursive: true,
    });
    expect(listen).toHaveBeenCalledWith(
      "quadrantShareSubmission",
      expect.any(Function),
    );
  });

  it("refetches modpacks when the filesystem watch fires", async () => {
    getModpacks.mockResolvedValue([pack({ name: "Original" })]);
    render(<ApplyPage />);

    await waitFor(() =>
      expect(screen.getByText("Original")).toBeInTheDocument(),
    );
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
    expect(() => shareCallback?.({ payload: { uses_left: 3 } })).not.toThrow();
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

  it("shows a Local badge and no Synced badge for a local-only modpack", async () => {
    getModpacks.mockResolvedValue([pack({ name: "Solo" })]);
    render(<ApplyPage />);

    await waitFor(() => expect(screen.getByText("Solo")).toBeInTheDocument());
    expect(screen.getByText("Local")).toBeInTheDocument();
    expect(screen.queryByText("Synced")).not.toBeInTheDocument();
    expect(screen.queryByText("Cloud")).not.toBeInTheDocument();
  });

  it("renders a local modpack and its cloud record as one card", async () => {
    getAccountInfo.mockResolvedValue({ login: "me", quadrant_sync_limit: 5 });
    getModpacks.mockResolvedValue([pack({ name: "Both", modpackId: "abc" })]);
    getSyncedModpacks.mockResolvedValue([
      cloudPack({ name: "Both", modpack_id: "abc" }),
    ]);
    render(<ApplyPage />);

    await waitFor(() => expect(screen.getByText("Synced")).toBeInTheDocument());
    expect(screen.getAllByText("Both")).toHaveLength(1);
    expect(screen.getByText("Local")).toBeInTheDocument();
    expect(screen.queryByText("Cloud")).not.toBeInTheDocument();
    // The merged card keeps the local action row; the cloud-only Download
    // button is not added to it.
    expect(screen.getByRole("button", { name: /^apply$/i })).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: /^download$/i }),
    ).not.toBeInTheDocument();
  });

  it("offers Force pull on a merged card's cloud panel", async () => {
    getAccountInfo.mockResolvedValue({ login: "me", quadrant_sync_limit: 5 });
    getModpacks.mockResolvedValue([pack({ name: "Both", modpackId: "abc" })]);
    getSyncedModpacks.mockResolvedValue([
      cloudPack({ name: "Both", modpack_id: "abc" }),
    ]);
    render(<ApplyPage />);

    await waitFor(() => expect(screen.getByText("Synced")).toBeInTheDocument());
    await userEvent.click(screen.getByRole("button", { name: /quadrant sync/i }));

    expect(
      screen.getByRole("button", { name: /^force pull$/i }),
    ).toBeInTheDocument();
  });

  it("refreshes the cloud list right after a local modpack is pushed", async () => {
    getAccountInfo.mockResolvedValue({ login: "me", quadrant_sync_limit: 5 });
    getModpacks.mockResolvedValue([pack({ name: "Fresh", modpackId: "abc" })]);
    syncModpack.mockResolvedValue(undefined);
    render(<ApplyPage />);

    await waitFor(() => expect(screen.getByText("Fresh")).toBeInTheDocument());
    await waitFor(() => expect(getSyncedModpacks).toHaveBeenCalledTimes(1));
    expect(screen.queryByText("Synced")).not.toBeInTheDocument();

    // The push creates the cloud record; the badge must appear without any
    // backend event or remount.
    getSyncedModpacks.mockResolvedValue([
      cloudPack({ name: "Fresh", modpack_id: "abc" }),
    ]);
    await userEvent.click(screen.getByRole("button", { name: /^sync$/i }));

    await waitFor(() => expect(screen.getByText("Synced")).toBeInTheDocument());
  });

  it("renders a cloud-only modpack with Cloud and Synced badges", async () => {
    getAccountInfo.mockResolvedValue({ login: "me", quadrant_sync_limit: 5 });
    getSyncedModpacks.mockResolvedValue([
      cloudPack({ name: "Remote", modpack_id: "xyz" }),
    ]);
    render(<ApplyPage />);

    await waitFor(() => expect(screen.getByText("Remote")).toBeInTheDocument());
    expect(screen.getByText("Cloud")).toBeInTheDocument();
    expect(screen.getByText("Synced")).toBeInTheDocument();
    expect(screen.queryByText("Local")).not.toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /^download$/i }),
    ).toBeInTheDocument();
  });

  it("installs a cloud-only modpack in place from its Download button", async () => {
    getAccountInfo.mockResolvedValue({ login: "me", quadrant_sync_limit: 5 });
    getSyncedModpacks.mockResolvedValue([
      cloudPack({
        name: "Remote",
        modpack_id: "xyz",
        mods: JSON.stringify([{ id: "sodium", source: "ModSource.modRinth" }]),
        last_synced: 42,
      }),
    ]);
    installModpack.mockResolvedValue(undefined);
    render(
      <SpiedContent>
        <ApplyPage />
      </SpiedContent>,
    );

    await waitFor(() => expect(screen.getByText("Remote")).toBeInTheDocument());
    await userEvent.click(screen.getByRole("button", { name: /^download$/i }));

    await waitFor(() =>
      expect(installModpack).toHaveBeenCalledWith({
        name: "Remote",
        mods: [{ id: "sodium", source: "ModSource.modRinth" }],
        modLoader: ModLoader.Fabric,
        version: "1.20.1",
      }),
    );
    // The install is stamped with the cloud sync date so the pack pairs up.
    await waitFor(() =>
      expect(invoke).toHaveBeenCalledWith("set_modpack_sync_date", {
        time: 42,
        modpack: "Remote",
        modpackId: "xyz",
      }),
    );
    expect(changeContent).not.toHaveBeenCalled();
  });

  it("opens the details view of a cloud-only modpack without installing", async () => {
    getAccountInfo.mockResolvedValue({ login: "me", quadrant_sync_limit: 5 });
    getSyncedModpacks.mockResolvedValue([
      cloudPack({ name: "Remote", modpack_id: "xyz" }),
    ]);
    render(
      <SpiedContent>
        <ApplyPage />
      </SpiedContent>,
    );

    await waitFor(() => expect(screen.getByText("Remote")).toBeInTheDocument());
    await userEvent.click(screen.getByRole("button", { name: /^details$/i }));

    expect(changeContent).toHaveBeenCalledWith(
      expect.objectContaining({ title: "Remote" }),
    );
    expect(installModpack).not.toHaveBeenCalled();
  });

  it("force pulls a merged modpack in place", async () => {
    getAccountInfo.mockResolvedValue({ login: "me", quadrant_sync_limit: 5 });
    getModpacks.mockResolvedValue([pack({ name: "Both", modpackId: "abc" })]);
    getSyncedModpacks.mockResolvedValue([
      cloudPack({ name: "Both", modpack_id: "abc" }),
    ]);
    installModpack.mockResolvedValue(undefined);
    render(
      <SpiedContent>
        <ApplyPage />
      </SpiedContent>,
    );

    await waitFor(() => expect(screen.getByText("Synced")).toBeInTheDocument());
    await userEvent.click(screen.getByRole("button", { name: /quadrant sync/i }));
    await userEvent.click(screen.getByRole("button", { name: /^force pull$/i }));

    await waitFor(() =>
      expect(installModpack).toHaveBeenCalledWith(
        expect.objectContaining({ name: "Both" }),
      ),
    );
    expect(changeContent).not.toHaveBeenCalled();
  });

  it("filters cloud-only modpacks by the search query", async () => {
    getAccountInfo.mockResolvedValue({ login: "me", quadrant_sync_limit: 5 });
    getSyncedModpacks.mockResolvedValue([
      cloudPack({ name: "Alpha", modpack_id: "1" }),
      cloudPack({ name: "Beta", modpack_id: "2" }),
    ]);
    render(<ApplyPage />);

    await waitFor(() => expect(screen.getByText("Beta")).toBeInTheDocument());
    await userEvent.type(screen.getByRole("textbox"), "alp");

    await waitFor(() =>
      expect(screen.queryByText("Beta")).not.toBeInTheDocument(),
    );
    expect(screen.getByText("Alpha")).toBeInTheDocument();
  });

  it("hides the cloud list when the account has no sync quota", async () => {
    getAccountInfo.mockResolvedValue({ login: "me", quadrant_sync_limit: 0 });
    getSyncedModpacks.mockResolvedValue([
      cloudPack({ name: "Remote", modpack_id: "xyz" }),
    ]);
    render(<ApplyPage />);

    await waitFor(() => expect(getAccountInfo).toHaveBeenCalled());
    expect(getSyncedModpacks).not.toHaveBeenCalled();
    expect(screen.queryByText("Remote")).not.toBeInTheDocument();
  });

  it("accepts text pasted directly into the search field", async () => {
    const user = userEvent.setup();
    render(<ApplyPage />);

    await user.click(screen.getByRole("textbox"));
    await user.paste("  1234567  ");

    await waitFor(() =>
      expect(screen.getByRole("textbox")).toHaveValue("1234567"),
    );
    // Asserts the ref was updated too: updateModpacks reads it, not the state.
    await waitFor(() =>
      expect(getModpacks).toHaveBeenCalledWith(true, "1234567"),
    );
  });
});
