/** @format */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";

const getAccountInfo = vi.fn();
const startOAuthServer = vi.fn();
const cancelOAuthServer = vi.fn();
const onOAuthUrl = vi.fn();
const storeSet = vi.fn();

vi.mock("../../../tools", () => ({
  clearAccountToken: vi.fn(),
  getAccountInfo: (...a: unknown[]) => getAccountInfo(...a),
  openIn: vi.fn(),
}));

vi.mock("../../../desktop", () => ({
  cancelOAuthServer: (...a: unknown[]) => cancelOAuthServer(...a),
  createDesktopStore: () => ({
    get: vi.fn().mockResolvedValue(null),
    set: (...a: unknown[]) => storeSet(...a),
  }),
  invoke: vi.fn().mockResolvedValue("client-id"),
  listen: vi.fn().mockResolvedValue(() => {}),
  onOAuthUrl: (...a: unknown[]) => onOAuthUrl(...a),
  startOAuthServer: (...a: unknown[]) => startOAuthServer(...a),
}));

import AccountPage from "./AccountPage";
import en from "../../../locales/en.json";

beforeEach(() => {
  vi.clearAllMocks();
  getAccountInfo.mockRejectedValue("errorSignedOut");
  storeSet.mockResolvedValue(undefined);
  cancelOAuthServer.mockResolvedValue(undefined);
  onOAuthUrl.mockResolvedValue(() => {});
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("AccountPage", () => {
  it("shows the sign-in screen when the backend reports no session", async () => {
    render(<AccountPage />);

    expect(
      await screen.findByRole("button", { name: en.signInWithOAuth }),
    ).toBeInTheDocument();
    expect(screen.queryByText(en.accountUnreachable)).not.toBeInTheDocument();
  });

  it("keeps the session when Quadrant ID is unreachable, and retries into it", async () => {
    getAccountInfo.mockRejectedValue("errorNetwork");
    render(<AccountPage />);

    expect(await screen.findByText(en.accountUnreachable)).toBeInTheDocument();
    expect(screen.getByText(en.errorNetwork)).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: en.signInWithOAuth }),
    ).not.toBeInTheDocument();

    getAccountInfo.mockResolvedValue({
      name: "Steve",
      email: "steve@example.com",
      login: "steve",
      quadrant_sync_limit: 5,
      quadrant_share_limit: 5,
      notifications: [],
    });
    fireEvent.click(screen.getByRole("button", { name: en.retry }));

    expect(
      await screen.findByText(en.hello.replace("{{name}}", "Steve")),
    ).toBeInTheDocument();
    expect(getAccountInfo).toHaveBeenCalledTimes(2);
  });

  it("starts a single OAuth callback server when sign-in is clicked twice", async () => {
    let releaseServer!: (port: number) => void;
    startOAuthServer.mockReturnValue(
      new Promise<number>((resolve) => {
        releaseServer = resolve;
      }),
    );
    render(<AccountPage />);
    const signIn = await screen.findByRole("button", {
      name: en.signInWithOAuth,
    });

    fireEvent.click(signIn);
    fireEvent.click(signIn);
    await waitFor(() => expect(startOAuthServer).toHaveBeenCalledTimes(1));
    expect(signIn).toBeDisabled();

    await act(async () => releaseServer(4000));
    await waitFor(() => expect(onOAuthUrl).toHaveBeenCalledTimes(1));
    expect(startOAuthServer).toHaveBeenCalledTimes(1);
    expect(cancelOAuthServer).not.toHaveBeenCalled();
    await waitFor(() => expect(signIn).not.toBeDisabled());
  });

  it("re-enables sign-in after the callback server fails to start", async () => {
    startOAuthServer.mockRejectedValue(new Error("port busy"));
    render(<AccountPage />);
    const signIn = await screen.findByRole("button", {
      name: en.signInWithOAuth,
    });

    fireEvent.click(signIn);
    await waitFor(() => expect(startOAuthServer).toHaveBeenCalledTimes(1));
    await waitFor(() => expect(signIn).not.toBeDisabled());

    fireEvent.click(signIn);
    await waitFor(() => expect(startOAuthServer).toHaveBeenCalledTimes(2));
  });
});
