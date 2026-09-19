/** @format */

/** The floating panel of a Headless UI `MenuItems`, anchored below its button. */
export const menuPanelClass =
  "z-50 [--anchor-gap:8px] flex flex-col p-2 font-bold bg-slate-800 rounded-4xl w-max max-w-80 max-h-80 overflow-y-auto shadow-lg shadow-slate-950";

/** One entry of such a panel. The layout of its contents is the caller's. */
export const menuItemClass =
  "text-left w-full px-4 py-2 rounded-4xl hover:bg-slate-700 data-focus:bg-slate-700 disabled:opacity-50 disabled:cursor-default hover:cursor-pointer";
