/** @format */

import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import {
  ContentContext,
  ModLoader,
  type PrismInstance,
} from "../../../intefaces";

const exportModpack = vi.fn();
const applyModpackToPrismInstance = vi.fn();
const detachPrismInstance = vi.fn();

vi.mock("../../../tools", () => ({
  applyModpack: vi.fn(),
  applyModpackToPrismInstance: (...a: unknown[]) =>
    applyModpackToPrismInstance(...a),
  deleteModpack: vi.fn(),
  detachPrismInstance: (...a: unknown[]) => detachPrismInstance(...a),
  exportModpack: (...a: unknown[]) => exportModpack(...a),
  shareModpack: vi.fn(),
  syncModpack: vi.fn(),
}));

import LocalModpackCard from "./LocalModpackCard";

const setSnackbar = vi.fn();

function instance(over: Partial<PrismInstance>): PrismInstance {
  return {
    id: "instance-1",
    name: "Survival",
    minecraftVersion: "1.20.1",
    modLoader: ModLoader.Fabric,
    modLoaderVersion: "0.15.0",
    appliedModpack: null,
    ...over,
  };
}

function renderCard(
  props: { prismInstances?: PrismInstance[]; onChanged?: () => void } = {},
) {
  return render(
    <ContentContext.Provider
      value={{
        back: () => {},
        setSnackbar,
        changeContent: () => {},
        changePage: () => {},
        setSnackbarNoState: () => {},
      }}
    >
      <LocalModpackCard
        modpack={{
          name: "Alpha Pack",
          version: "1.20.1",
          modLoader: ModLoader.Fabric,
          isApplied: false,
          lastSynced: 0,
          mods: [],
          unknownMods: false,
        }}
        prismInstances={props.prismInstances}
        onChanged={props.onChanged ?? (() => {})}
        onEdit={() => {}}
      />
    </ContentContext.Provider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("LocalModpackCard", () => {
  it("surfaces an export failure through the error snackbar", async () => {
    // The export must be awaited; otherwise the rejection escapes the catch
    // and the user is never told the export failed.
    exportModpack.mockRejectedValue("exportFailed");
    renderCard();

    await userEvent.click(screen.getByRole("button", { name: /export/i }));

    await waitFor(() => expect(setSnackbar).toHaveBeenCalledTimes(1));
    expect(setSnackbar.mock.calls[0][0]).toMatchObject({
      className: expect.stringContaining("bg-red-700"),
    });
  });

  it("does not show an error when the export succeeds", async () => {
    exportModpack.mockResolvedValue(undefined);
    renderCard();

    await userEvent.click(screen.getByRole("button", { name: /export/i }));

    await waitFor(() =>
      expect(exportModpack).toHaveBeenCalledWith("Alpha Pack"),
    );
    expect(setSnackbar).not.toHaveBeenCalled();
  });
});

describe("LocalModpackCard Prism Launcher menu", () => {
  it("offers no Prism button without instances", () => {
    renderCard();
    expect(
      screen.queryByRole("button", { name: /prism launcher/i }),
    ).not.toBeInTheDocument();

    renderCard({ prismInstances: [] });
    expect(
      screen.queryByRole("button", { name: /prism launcher/i }),
    ).not.toBeInTheDocument();
  });

  it("lists every instance with its version and loader", async () => {
    renderCard({
      prismInstances: [
        instance({ id: "a", name: "Survival" }),
        instance({
          id: "b",
          name: "Creative",
          minecraftVersion: "1.21",
          modLoader: ModLoader.NeoForge,
        }),
      ],
    });

    await userEvent.click(
      screen.getByRole("button", { name: /prism launcher/i }),
    );

    expect(
      screen.getByRole("menuitem", { name: /Survival/ }),
    ).toHaveTextContent("1.20.1 | Fabric");
    expect(
      screen.getByRole("menuitem", { name: /Creative/ }),
    ).toHaveTextContent("1.21 | NeoForge");
  });

  it("warns that a mismatched instance will be switched over", async () => {
    renderCard({
      prismInstances: [
        instance({ minecraftVersion: "1.21", modLoader: ModLoader.NeoForge }),
      ],
    });

    await userEvent.click(
      screen.getByRole("button", { name: /prism launcher/i }),
    );

    expect(
      screen.getByText("Will be switched to 1.20.1 · Fabric"),
    ).toBeInTheDocument();
  });

  it("names only the parts that differ, and nothing on a linked instance", async () => {
    renderCard({
      prismInstances: [
        instance({ id: "a", name: "Survival", minecraftVersion: "1.21" }),
        instance({
          id: "b",
          name: "Creative",
          minecraftVersion: "1.21",
          appliedModpack: "Alpha Pack",
        }),
      ],
    });

    await userEvent.click(
      screen.getByRole("button", { name: /prism launcher/i }),
    );

    expect(
      screen.getByRole("menuitem", { name: /Survival/ }),
    ).toHaveTextContent("Will be switched to 1.20.1");
    expect(
      screen.getByRole("menuitem", { name: /Survival/ }),
    ).not.toHaveTextContent("· Fabric");
    expect(
      screen.getByRole("menuitem", { name: /Creative/ }),
    ).not.toHaveTextContent("Will be switched");
  });

  it("applies the modpack to an unlinked instance and refreshes", async () => {
    const onChanged = vi.fn();
    applyModpackToPrismInstance.mockResolvedValue(undefined);
    renderCard({ prismInstances: [instance({ id: "a" })], onChanged });

    await userEvent.click(
      screen.getByRole("button", { name: /prism launcher/i }),
    );
    await userEvent.click(screen.getByRole("menuitem", { name: /Survival/ }));

    await waitFor(() =>
      expect(applyModpackToPrismInstance).toHaveBeenCalledWith(
        "Alpha Pack",
        "a",
      ),
    );
    expect(detachPrismInstance).not.toHaveBeenCalled();
    expect(onChanged).toHaveBeenCalled();
    expect(setSnackbar.mock.calls[0][0]).toMatchObject({
      className: "bg-emerald-600 rounded-4xl",
    });
  });

  it("detaches an instance that is already linked to this modpack", async () => {
    detachPrismInstance.mockResolvedValue(undefined);
    renderCard({
      prismInstances: [instance({ id: "a", appliedModpack: "Alpha Pack" })],
    });

    await userEvent.click(
      screen.getByRole("button", { name: /prism launcher/i }),
    );
    await userEvent.click(screen.getByRole("menuitem", { name: /Survival/ }));

    await waitFor(() => expect(detachPrismInstance).toHaveBeenCalledWith("a"));
    expect(applyModpackToPrismInstance).not.toHaveBeenCalled();
  });

  it("reports a failed apply through the error snackbar", async () => {
    applyModpackToPrismInstance.mockRejectedValue("errorPrismInstanceMissing");
    renderCard({ prismInstances: [instance({})] });

    await userEvent.click(
      screen.getByRole("button", { name: /prism launcher/i }),
    );
    await userEvent.click(screen.getByRole("menuitem", { name: /Survival/ }));

    await waitFor(() => expect(setSnackbar).toHaveBeenCalledTimes(1));
    expect(setSnackbar.mock.calls[0][0]).toMatchObject({
      className: "bg-red-700",
      message: "That Prism Launcher instance no longer exists.",
    });
  });

  it("names the instances this modpack is applied to", () => {
    renderCard({
      prismInstances: [
        instance({ id: "a", name: "Survival", appliedModpack: "Alpha Pack" }),
        instance({ id: "b", name: "Creative", appliedModpack: "Alpha Pack" }),
        instance({ id: "c", name: "Other", appliedModpack: "Beta Pack" }),
      ],
    });

    expect(
      screen.getByText("Applied to Prism Launcher: Survival, Creative"),
    ).toBeInTheDocument();
  });
});
