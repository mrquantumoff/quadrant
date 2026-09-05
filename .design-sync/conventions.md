## Building with Quadrant UI

Quadrant is a desktop (Tauri) app for managing Minecraft mods and modpacks. Its
UI is **React 19 + Tailwind CSS v4**, dark-themed, with an Inter typeface. Build
with these real components; style your own layout glue with the Tailwind classes
below.

### Setup — usually nothing

- Components render standalone. i18n is initialized by the bundle, so text
  renders in English automatically — no provider needed.
- **Data comes from props, not the backend.** In the app these components fetch
  data through a desktop runtime (`invoke`) that does **not** exist outside the
  Tauri shell — calling it throws "Quadrant desktop runtime is unavailable". So
  when you compose a screen, **pass data in as props** (a `Mod`'s metadata, a
  modpack list) rather than expecting it to load itself. Page components
  (`SettingsPage`, `AccountPage`, `SharedModpackView`, …) paint their chrome fine; their
  live data lists stay empty in a design environment.
- Apply combines local and cloud modpacks. Pass a manifest to
  `SharedModpackView`, and cloud records plus account info to `SyncedModpack`
  or `CloudMembersPanel`. Cloud management actions use `SyncContext` to refresh
  the parent list.

### Styling idiom — Tailwind v4 utilities

There is **no separate CSS API**: style everything with Tailwind utility classes
(the same ones the app uses). The palette is slate-based dark:

| Purpose | Classes |
|---|---|
| App background / surfaces | `bg-slate-900` (page), `bg-slate-800` / `bg-slate-700` (cards, inputs) |
| Text | `text-slate-50` (default), `text-slate-400` (muted) |
| Primary action | `bg-blue-600 hover:bg-blue-700` |
| Positive / create | `bg-emerald-600 hover:bg-emerald-700` |
| Neutral action | `bg-slate-800 hover:bg-slate-700` |
| Destructive | `bg-slate-800 hover:bg-red-700` |
| Rounding | `rounded-full` / `rounded-4xl` (pills everywhere) |
| Type | Inter, `font-normal`; `font-extrabold` on buttons |

Custom classes shipped in the stylesheet: `.input` (styled text field),
`.center` (grid place-items-center), `.page` (full-width), `.disableSelect`.
Icons come from `react-icons` (e.g. `react-icons/fa6`).

### Where the real detail lives

Read the bound stylesheet `styles.css` (and its `@import`ed `_ds_bundle.css` /
`tokens/`) for exact tokens, and each component's `<Name>.d.ts` (props) and
`<Name>.prompt.md` (usage) before composing.

### Idiomatic snippet

```tsx
import { Button } from "quadrant-next";
import { FaPlus } from "react-icons/fa6";

<div className="bg-slate-900 p-6 flex gap-3">
  <Button className="bg-emerald-600 hover:bg-emerald-700 text-slate-50" onClick={createModpack}>
    <span className="flex items-center gap-2"><FaPlus /> Create a new modpack</span>
  </Button>
  <Button className="bg-slate-800 hover:bg-slate-700 text-slate-50" onClick={openFolder}>
    Open modpacks folder
  </Button>
</div>
```
