/** @format */

import { createDesktopStore } from "./desktop";

export const UI_SCALE_KEY = "uiScale";
/** Default UI scale (percent). */
export const COMPACT_UI_SCALE = 100;
export const MIN_UI_SCALE = 50;
export const MAX_UI_SCALE = 200;
export const UI_SCALE_STEP = 10;

/**
 * Root font size in px at 100% scale. Keep in sync with App.css.
 * What used to be 120% is now the 100% default; every other scale
 * value is a percentage of this base.
 */
const BASE_ROOT_FONT_PX = 16.8;

export function clampUiScale(scale: number | null | undefined): number {
  if (typeof scale !== "number" || !Number.isFinite(scale)) {
    return COMPACT_UI_SCALE;
  }
  return Math.min(MAX_UI_SCALE, Math.max(MIN_UI_SCALE, Math.round(scale)));
}

/**
 * Scales the whole UI by adjusting the root font size, which every
 * rem-based Tailwind size and spacing derives from.
 */
export function applyUiScale(scale: number | null | undefined) {
  const clamped = clampUiScale(scale);
  document.documentElement.style.fontSize = `${
    (BASE_ROOT_FONT_PX * clamped) / 100
  }px`;
}

/** Reads the scale currently applied to the document. */
export function getAppliedUiScale(): number {
  const px = parseFloat(getComputedStyle(document.documentElement).fontSize);
  if (!Number.isFinite(px) || px <= 0) {
    return COMPACT_UI_SCALE;
  }
  return clampUiScale((px / BASE_ROOT_FONT_PX) * 100);
}

/** Applies the scale immediately and persists it to the config store. */
export async function setUiScale(scale: number): Promise<number> {
  const clamped = clampUiScale(scale);
  applyUiScale(clamped);
  const config = createDesktopStore("config.json");
  await config.set(UI_SCALE_KEY, clamped);
  await config.save();
  return clamped;
}
