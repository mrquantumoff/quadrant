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

beforeEach(() => {
  vi.clearAllMocks();
  getAccountInfo.mockResolvedValue(null);
  storeSet.mockResolvedValue(undefined);
  cancelOAuthServer.mockResolvedValue(undefined);
  onOAuthUrl.mockResolvedValue(() => {});
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("AccountPage", () => {
  it("starts a single OAuth callback server when sign-in is clicked twice", async () => {
    let releaseServer!: (port: number) => void;
    startOAuthServer.mockReturnValue(
      new Promise<number>((resolve) => {
        releaseServer = resolve;
      }),
    );
    render(<AccountPage />);
    const signIn = await screen.findByRole("button", {
      name: /sign ?in ?with/i,
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
      name: /sign ?in ?with/i,
    });

    fireEvent.click(signIn);
    await waitFor(() => expect(startOAuthServer).toHaveBeenCalledTimes(1));
    await waitFor(() => expect(signIn).not.toBeDisabled());

    fireEvent.click(signIn);
    await waitFor(() => expect(startOAuthServer).toHaveBeenCalledTimes(2));
  });
});
