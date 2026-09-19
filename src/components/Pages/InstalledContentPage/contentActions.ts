/** @format */

import { ContentLocation, ModType } from "../../../intefaces";

/** One section of one location: everything an action needs to address it. */
export interface SectionRef {
  locationId: string;
  modType: ModType;
}

/** Files of one section, as one `copyContent` or `deleteContent` call. */
export interface SectionFiles extends SectionRef {
  fileNames: string[];
}

/** One ticked file, remembered with the section it was ticked in. */
export interface SelectedFile extends SectionRef {
  fileName: string;
}

/** Identifies one section of one location; keys a {@link FileNameIndex}. */
export function sectionKey(ref: SectionRef): string {
  return `${ref.locationId}|${ref.modType}`;
}

/** Identifies the control an action was started from, so only it reacts. */
export function controlKey(ref: SectionRef, fileName: string): string {
  return `${sectionKey(ref)}|${fileName}`;
}

/** The "copy all" control of a section, apart from any of its files'. */
export function copyAllControlKey(ref: SectionRef): string {
  return controlKey(ref, "#all");
}

/** The page-level selection bar's controls, apart from every section's. */
export const selectionControlKey = "#selection";

/** The names every location holds, keyed by {@link sectionKey}. */
export type FileNameIndex = Map<string, Set<string>>;

const NO_FILE_NAMES: Set<string> = new Set();

/** Indexes the whole listing once, so a copy check is a lookup per target. */
export function indexFileNames(locations: ContentLocation[]): FileNameIndex {
  const index: FileNameIndex = new Map();
  for (const location of locations) {
    for (const section of location.sections) {
      index.set(
        sectionKey({ locationId: location.id, modType: section.modType }),
        new Set(section.files.map((file) => file.fileName)),
      );
    }
  }
  return index;
}

function namesIn(index: FileNameIndex, ref: SectionRef): Set<string> {
  return index.get(sectionKey(ref)) ?? NO_FILE_NAMES;
}

export interface CopyTarget {
  location: ContentLocation;
  /** One copy per source section, never from the destination itself. */
  groups: SectionFiles[];
  /** How many files would move, across every group. */
  count: number;
}

/**
 * Every location a copy could go to, paired with the work it would do there:
 * the given files, minus the ones that already come from that location and the
 * ones it already holds. A destination everything came from is not offered.
 */
export function copyTargets(
  locations: ContentLocation[],
  index: FileNameIndex,
  files: SelectedFile[],
): CopyTarget[] {
  const sources = groupBySection(files);
  return locations
    .filter((location) =>
      sources.some((source) => source.locationId !== location.id),
    )
    .map((location) => {
      const groups = sources
        .filter((source) => source.locationId !== location.id)
        .map((source) => {
          const present = namesIn(index, {
            locationId: location.id,
            modType: source.modType,
          });
          return {
            ...source,
            fileNames: source.fileNames.filter((name) => !present.has(name)),
          };
        })
        .filter((group) => group.fileNames.length > 0);
      return { location, groups, count: countFiles(groups) };
    });
}

/** How many files a run of copies or deletes would touch. */
export function countFiles(groups: SectionFiles[]): number {
  return groups.reduce((total, group) => total + group.fileNames.length, 0);
}

function sameSection(a: SectionRef, b: SectionRef): boolean {
  return a.locationId === b.locationId && a.modType === b.modType;
}

/** The names ticked in this section, in ticking order. */
export function selectedIn(
  selection: SelectedFile[],
  ref: SectionRef,
): string[] {
  return selection
    .filter((file) => sameSection(file, ref))
    .map((file) => file.fileName);
}

/** Ticks or unticks one file, leaving every tick made elsewhere alone. */
export function toggleSelection(
  selection: SelectedFile[],
  file: SelectedFile,
): SelectedFile[] {
  const without = selection.filter(
    (entry) => !(sameSection(entry, file) && entry.fileName === file.fileName),
  );
  return without.length === selection.length ? [...selection, file] : without;
}

/** Adds every one of a section's files, keeping the ticks made elsewhere. */
export function selectAllIn(
  selection: SelectedFile[],
  ref: SectionRef,
  fileNames: string[],
): SelectedFile[] {
  const ticked = new Set(selectedIn(selection, ref));
  return [
    ...selection,
    ...fileNames
      .filter((fileName) => !ticked.has(fileName))
      .map((fileName) => ({ ...ref, fileName })),
  ];
}

/** Forgets every tick a reload no longer reports. */
export function pruneSelection(
  selection: SelectedFile[],
  locations: ContentLocation[],
): SelectedFile[] {
  const index = indexFileNames(locations);
  return selection.filter((file) => namesIn(index, file).has(file.fileName));
}

/** The selection as one request per section, in first-ticked order. */
export function groupBySection(selection: SelectedFile[]): SectionFiles[] {
  const groups = new Map<string, SectionFiles>();
  for (const file of selection) {
    const group = groups.get(sectionKey(file));
    if (group === undefined) {
      groups.set(sectionKey(file), {
        locationId: file.locationId,
        modType: file.modType,
        fileNames: [file.fileName],
      });
    } else {
      group.fileNames.push(file.fileName);
    }
  }
  return [...groups.values()];
}
