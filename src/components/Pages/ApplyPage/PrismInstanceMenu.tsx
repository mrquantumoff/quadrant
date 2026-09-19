/** @format */

import { useRef, useState } from "react";
import { Menu, MenuButton, MenuItem, MenuItems } from "@headlessui/react";
import { MdCheck, MdViewList } from "react-icons/md";
import { useTranslation } from "react-i18next";
import { LocalModpack, PrismInstance, PrismSyncPlan } from "../../../intefaces";
import {
  applyModpackToPrismInstance,
  detachPrismInstance,
  getPrismSyncPlans,
} from "../../../tools";
import { menuItemClass, menuPanelClass } from "../../core/menuClasses";
import { useReportError } from "../../../useReportError";
import { useReportSuccess } from "../../../useReportSuccess";

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
  // What the host says applying would rewrite, or null until it has answered.
  const [plans, setPlans] = useState<PrismSyncPlan[] | null>(null);
  // There is one menu per modpack card, so the plans wait for a first opening.
  const askedRef = useRef(false);

  const loadPlans = async () => {
    try {
      setPlans(await getPrismSyncPlans(modpack.name));
    } catch (error) {
      // The hint is an extra; losing it must not cost the user the menu.
      console.error(error);
    }
  };

  const open = () => {
    if (askedRef.current) {
      return;
    }
    askedRef.current = true;
    void loadPlans();
  };

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
      await loadPlans();
      reportSuccess(t(linked ? "prismDetachSuccess" : "prismApplySuccess"));
    } catch (e: any) {
      reportError(e);
    } finally {
      setPendingId(null);
    }
  };

  return (
    <Menu as="div" className="relative m-2 self-center">
      <MenuButton
        onClick={open}
        className="rounded-4xl p-2 font-extrabold hover:cursor-pointer flex items-center bg-slate-800 hover:bg-slate-700 px-4 w-max h-10 justify-center"
      >
        {t("prismLauncher")}
        <MdViewList className="w-5 h-5 mx-2" />
      </MenuButton>
      <MenuItems anchor="bottom start" className={menuPanelClass}>
        {instances.map((instance) => {
          const linked = instance.appliedModpack === modpack.name;
          const plan = plans?.find((entry) => entry.instanceId === instance.id);
          const switchTarget =
            linked || plan === undefined
              ? []
              : [plan.minecraftVersion, plan.modLoader].filter(
                  (part): part is string => part !== null,
                );
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
