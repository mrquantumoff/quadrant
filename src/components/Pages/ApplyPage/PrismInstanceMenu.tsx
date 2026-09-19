/** @format */

import { useState } from "react";
import { Menu, MenuButton, MenuItem, MenuItems } from "@headlessui/react";
import { MdCheck, MdViewList } from "react-icons/md";
import { useTranslation } from "react-i18next";
import { LocalModpack, ModLoader, PrismInstance } from "../../../intefaces";
import {
  applyModpackToPrismInstance,
  detachPrismInstance,
} from "../../../tools";
import { menuItemClass, menuPanelClass } from "../../core/menuClasses";
import { useReportError } from "../../../useReportError";
import { useReportSuccess } from "../../../useReportSuccess";

// Prism only has components for these; the backend leaves any other loader,
// and a modpack without a manifest version, untouched.
const PRISM_LOADERS: readonly ModLoader[] = [
  ModLoader.Fabric,
  ModLoader.Quilt,
  ModLoader.Forge,
  ModLoader.NeoForge,
];

/** The parts of the instance that applying `modpack` will rewrite. */
function switchedParts(instance: PrismInstance, modpack: LocalModpack) {
  const parts: string[] = [];
  const hasVersion = modpack.version !== "" && modpack.version !== "-";
  if (hasVersion && instance.minecraftVersion !== modpack.version) {
    parts.push(modpack.version);
  }
  if (
    hasVersion &&
    PRISM_LOADERS.includes(modpack.modLoader) &&
    instance.modLoader !== modpack.modLoader
  ) {
    parts.push(modpack.modLoader);
  }
  return parts;
}

export interface PrismInstanceMenuProps {
  modpack: LocalModpack;
  instances: PrismInstance[];
  onChanged: () => void | Promise<void>;
}

export default function PrismInstanceMenu({
  modpack,
  instances,
  onChanged,
}: PrismInstanceMenuProps) {
  const { t } = useTranslation();
  const reportError = useReportError();
  const reportSuccess = useReportSuccess();
  // The id of the instance whose request is in flight, or null when idle. One
  // request at a time keeps a double click from applying and detaching at once.
  const [pendingId, setPendingId] = useState<string | null>(null);

  const toggle = async (instance: PrismInstance) => {
    if (pendingId !== null) {
      return;
    }
    const linked = instance.appliedModpack === modpack.name;
    setPendingId(instance.id);
    try {
      if (linked) {
        await detachPrismInstance(instance.id);
      } else {
        await applyModpackToPrismInstance(modpack.name, instance.id);
      }
      await onChanged();
      reportSuccess(t(linked ? "prismDetachSuccess" : "prismApplySuccess"));
    } catch (e: any) {
      reportError(e);
    } finally {
      setPendingId(null);
    }
  };

  return (
    <Menu as="div" className="relative m-2 self-center">
      <MenuButton className="rounded-4xl p-2 font-extrabold hover:cursor-pointer flex items-center bg-slate-800 hover:bg-slate-700 px-4 w-max h-10 justify-center">
        {t("prismLauncher")}
        <MdViewList className="w-5 h-5 mx-2" />
      </MenuButton>
      <MenuItems anchor="bottom start" className={menuPanelClass}>
        {instances.map((instance) => {
          const linked = instance.appliedModpack === modpack.name;
          const switchTarget = linked ? [] : switchedParts(instance, modpack);
          return (
            <MenuItem key={instance.id}>
              <button
                type="button"
                disabled={pendingId !== null}
                onClick={() => void toggle(instance)}
                className={"flex flex-col items-start " + menuItemClass}
              >
                <span className="flex items-center gap-2 w-full">
                  {instance.name}
                  {linked && <MdCheck className="w-5 h-5 ml-auto shrink-0" />}
                </span>
                <span className="text-md text-slate-400">
                  {instance.minecraftVersion ?? t("unknown")} |{" "}
                  {instance.modLoader}
                </span>
                {switchTarget.length > 0 && (
                  <span className="text-md text-slate-400">
                    {t("prismInstanceSwitchHint", {
                      target: switchTarget.join(" · "),
                    })}
                  </span>
                )}
              </button>
            </MenuItem>
          );
        })}
      </MenuItems>
    </Menu>
  );
}
