/** @format */

import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ContentContext, ModLoader } from "../../../intefaces";

const exportModpack = vi.fn();

vi.mock("../../../tools", () => ({
  applyModpack: vi.fn(),
  deleteModpack: vi.fn(),
  exportModpack: (...a: unknown[]) => exportModpack(...a),
  shareModpack: vi.fn(),
  syncModpack: vi.fn(),
}));

import LocalModpackCard from "./LocalModpackCard";

const setSnackbar = vi.fn();

function renderCard() {
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
        onChanged={() => {}}
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

    await waitFor(() => expect(exportModpack).toHaveBeenCalledWith("Alpha Pack"));
    expect(setSnackbar).not.toHaveBeenCalled();
  });
});
