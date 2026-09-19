/** @format */

import { ContentFile, ContentLocation, ModType } from "../../../intefaces";

/** The packs of one kind a location holds. Empty for a kind it never stores. */
export function filesOf(
  location: ContentLocation,
  modType: ModType,
): ContentFile[] {
  switch (modType) {
    case ModType.ResourcePack:
      return location.resourcePacks;
    case ModType.ShaderPack:
      return location.shaderPacks;
    default:
      return [];
  }
}

export interface CopyTarget {
  location: ContentLocation;
  /** The requested names this location does not hold yet, in request order. */
  missing: string[];
}

/**
 * Every location a copy could go to, paired with the work it would do there.
 * An empty `missing` means the destination already has all of `fileNames`.
 */
export function copyTargets(
  locations: ContentLocation[],
  sourceId: string,
  modType: ModType,
  fileNames: string[],
): CopyTarget[] {
  return locations
    .filter((location) => location.id !== sourceId)
    .map((location) => {
      const present = new Set(
        filesOf(location, modType).map((file) => file.fileName),
      );
      return {
        location,
        missing: fileNames.filter((fileName) => !present.has(fileName)),
      };
    });
}

/** Identifies the control an action was started from, so only it reacts. */
export function controlKey(
  locationId: string,
  modType: ModType,
  fileName?: string,
): string {
  return `${locationId}|${modType}|${fileName ?? "*"}`;
}

/** The key of a section's bulk controls, apart from any file's. */
export function selectionKey(locationId: string, modType: ModType): string {
  return controlKey(locationId, modType, "#selection");
}

/**
 * The ticked files. A copy or a delete takes one location and one kind of
 * pack, so a selection can never span two sections.
 */
export interface ContentSelection {
  locationId: string;
  modType: ModType;
  fileNames: string[];
}

/** The names ticked in this section; empty when the selection is elsewhere. */
export function selectedIn(
  selection: ContentSelection | null,
  locationId: string,
  modType: ModType,
): string[] {
  return selection !== null &&
    selection.locationId === locationId &&
    selection.modType === modType
    ? selection.fileNames
    : [];
}

/** Ticks or unticks one file, dropping a selection made in another section. */
export function toggleSelection(
  selection: ContentSelection | null,
  locationId: string,
  modType: ModType,
  fileName: string,
): ContentSelection | null {
  const current = selectedIn(selection, locationId, modType);
  const fileNames = current.includes(fileName)
    ? current.filter((name) => name !== fileName)
    : [...current, fileName];
  return fileNames.length === 0 ? null : { locationId, modType, fileNames };
}

/** Forgets names a reload no longer reports; an emptied selection is dropped. */
export function pruneSelection(
  selection: ContentSelection | null,
  locations: ContentLocation[],
): ContentSelection | null {
  if (selection === null) {
    return null;
  }
  const location = locations.find((entry) => entry.id === selection.locationId);
  if (location === undefined) {
    return null;
  }
  const present = new Set(
    filesOf(location, selection.modType).map((file) => file.fileName),
  );
  const fileNames = selection.fileNames.filter((name) => present.has(name));
  return fileNames.length === 0 ? null : { ...selection, fileNames };
}
