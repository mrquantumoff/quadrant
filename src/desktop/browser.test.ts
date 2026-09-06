/** @format */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { browserRuntime } from "./browser";
import type { UnlistenFn } from "./contract";
import { createDesktopStore } from "./index";
import { __setRuntimeForTests } from "./runtime";

const subscriptions: UnlistenFn[] = [];

beforeEach(() => {
  window.localStorage.clear();
  __setRuntimeForTests(browserRuntime);
});

afterEach(async () => {
  for (const unsubscribe of subscriptions.splice(0)) {
    await unsubscribe();
  }
  __setRuntimeForTests(undefined);
});

describe("browser settings subscriptions", () => {
  it("notifies subscribers through independently resolved store adapters", async () => {
    const reader = createDesktopStore("config.json");
    const writer = createDesktopStore("config.json");
    const onChange = vi.fn();
    const onScaleChange = vi.fn();
    subscriptions.push(await reader.onChange(onChange));
    subscriptions.push(await reader.onKeyChange("uiScale", onScaleChange));

    await writer.set("uiScale", 150);

    expect(await reader.get("uiScale")).toBe(150);
    expect(onChange).toHaveBeenCalledExactlyOnceWith("uiScale");
    expect(onScaleChange).toHaveBeenCalledExactlyOnceWith(150);
  });

  it("isolates store names and keys, including null values", async () => {
    const store = createDesktopStore("config.json");
    const listener = vi.fn();
    subscriptions.push(await store.onKeyChange("uiScale", listener));

    await createDesktopStore("other.json").set("uiScale", 200);
    await store.set("language", "tr");
    expect(listener).not.toHaveBeenCalled();

    await store.set("uiScale", null);
    expect(listener).toHaveBeenCalledExactlyOnceWith(null);
  });

  it("stops delivering changes after either kind of subscription is removed", async () => {
    const store = createDesktopStore("config.json");
    const onChange = vi.fn();
    const onKeyChange = vi.fn();
    const unsubscribeAll = await store.onChange(onChange);
    const unsubscribeKey = await store.onKeyChange("uiScale", onKeyChange);
    subscriptions.push(unsubscribeAll, unsubscribeKey);

    await unsubscribeAll();
    await unsubscribeKey();
    await store.set("uiScale", 150);

    expect(onChange).not.toHaveBeenCalled();
    expect(onKeyChange).not.toHaveBeenCalled();
  });

  it("preserves the previous value when a write cannot be serialized", async () => {
    const store = createDesktopStore("config.json");
    await store.set("uiScale", 150);

    await expect(store.set("uiScale", undefined)).rejects.toThrow(TypeError);
    expect(await store.get("uiScale")).toBe(150);
  });
});
