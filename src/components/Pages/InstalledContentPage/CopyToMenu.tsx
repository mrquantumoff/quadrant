/** @format */

import { Menu, MenuButton, MenuItem, MenuItems } from "@headlessui/react";
import { MdCheck, MdContentCopy } from "react-icons/md";
import { ContentLocation } from "../../../intefaces";

export interface CopyToOption {
  location: ContentLocation;
  label: string;
  /** Nothing left to copy there; the entry shows a check instead. */
  disabled: boolean;
}

export interface CopyToMenuProps {
  options: CopyToOption[];
  /** Screen-reader name of the button, naming what would be copied. */
  label: string;
  /** Visible button text. The compact per-file control leaves it out. */
  text?: string;
  /** This control started the copy that is running. */
  busy: boolean;
  /** Some copy is running, so no control may start another. */
  disabled: boolean;
  onPick: (destination: ContentLocation) => void;
}

export default function CopyToMenu({
  options,
  label,
  text,
  busy,
  disabled,
  onPick,
}: CopyToMenuProps) {
  return (
    <Menu as="div" className="relative shrink-0">
      <MenuButton
        aria-label={label}
        title={label}
        aria-busy={busy}
        disabled={disabled}
        className={
          "flex items-center justify-center h-10 rounded-4xl bg-slate-700 hover:bg-slate-600 font-extrabold text-sm hover:cursor-pointer disabled:opacity-50 disabled:cursor-default " +
          (text === undefined ? "w-10" : "w-max px-4")
        }
      >
        {text}
        <MdContentCopy
          aria-hidden="true"
          className={"w-5 h-5 " + (text === undefined ? "" : "ml-2")}
        />
      </MenuButton>
      <MenuItems
        anchor="bottom end"
        className="z-50 [--anchor-gap:8px] flex flex-col p-2 font-bold bg-slate-800 rounded-4xl w-max max-w-80 max-h-80 overflow-y-auto shadow-lg shadow-slate-950"
      >
        {options.map((option) => (
          <MenuItem key={option.location.id}>
            <button
              type="button"
              disabled={option.disabled}
              onClick={() => onPick(option.location)}
              className="flex items-center gap-2 text-left w-full px-4 py-2 rounded-4xl hover:bg-slate-700 data-focus:bg-slate-700 disabled:opacity-50 disabled:cursor-default hover:cursor-pointer"
            >
              <span className="min-w-0 break-words">{option.label}</span>
              {option.disabled && (
                <MdCheck
                  aria-hidden="true"
                  className="w-5 h-5 ml-auto shrink-0"
                />
              )}
            </button>
          </MenuItem>
        ))}
      </MenuItems>
    </Menu>
  );
}
