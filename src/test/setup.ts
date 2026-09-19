/** @format */

import "@testing-library/jest-dom/vitest";

// jsdom ships no ResizeObserver, and Headless UI's overlays observe their
// anchor as soon as they open. Layout is meaningless here, so never emit.
if (!("ResizeObserver" in globalThis)) {
  globalThis.ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
  } as unknown as typeof ResizeObserver;
}
