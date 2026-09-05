/**
 * design-sync barrel entry.
 * All Quadrant components are default exports; this re-exports them as named
 * exports so the converter can assign each to window.Quadrant.<Name>.
 * Referenced by cfg.entry — committed so re-sync is reproducible.
 *
 * Importing src/i18n runs its init side-effect (react-i18next uses a global
 * instance, no provider needed), so components render real translated copy.
 */
import "../src/i18n";

export { default as Button } from "../src/components/core/Button";
export { default as CircularProgress } from "../src/components/core/CircularProgress";
export { default as LinearProgress } from "../src/components/core/LinearProgress";

export { default as Mod } from "../src/components/shared/Mod";
export { default as Notifications } from "../src/components/shared/Notifications";
export { default as LoaderOption } from "../src/components/shared/LoaderOption";
export { default as ModpackView } from "../src/components/shared/Pages/ModpackView";

export { default as AccountPage } from "../src/components/Pages/AccountPage/AccountPage";
export { default as ApplyPage } from "../src/components/Pages/ApplyPage/Apply";
export { default as CloudModpackSection } from "../src/components/Pages/ApplyPage/CloudModpackSection";
export { default as CurrentModpackPage } from "../src/components/Pages/CurrentModpackPage/CurrentModpackPage";
export { default as ModInstallPage } from "../src/components/Pages/ModInstallPage/ModInstallPage";
export { default as SearchPage } from "../src/components/Pages/SearchPage/SearchPage";
export { default as SettingsPage } from "../src/components/Pages/SettingsPage/Settings";
export { default as SharedModpackView } from "../src/components/Pages/ApplyPage/SharedModpackView";
export { default as SyncedModpack } from "../src/components/Pages/ApplyPage/SyncedModpack";
