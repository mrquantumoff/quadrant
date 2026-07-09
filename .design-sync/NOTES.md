# Quadrant UI — design-sync notes

Quadrant is a **Tauri desktop app**, not a published component library, so the
sync is wired by hand. Key setup (all committed):

- **Barrel entry** `.design-sync/ds-entry.tsx` — every component is a *default*
  export, so synth mode's `export *` would ship an empty bundle. The barrel
  re-exports them as named exports and also `import "../src/i18n"` so i18n
  initializes (react-i18next global instance, no provider). `cfg.entry` points
  at it; its walk-up also fixes `PKG_DIR` (repo root, since the repo doesn't
  self-install `node_modules/quadrant-next`).
- **`cfg.componentSrcMap`** enumerates all 17 components (no `.d.ts` to discover
  from). Update it when components are added/removed/renamed.
- **CSS is Tailwind v4.** `.design-sync/build-css.mjs` compiles `src/App.css`
  with the repo's own `@tailwindcss/postcss` into
  `.design-sync/quadrant-compiled.css` (= `cfg.cssEntry`) and copies
  `public/Inter-Font.ttf` beside it. **Re-run `node .design-sync/build-css.mjs`
  before every (re)build** — the output is gitignored.
- **Tailwind esbuild shim.** Component CSS files do `@import "tailwindcss"`
  (a PostCSS directive esbuild can't resolve). `.design-sync/tsconfig.sync.json`
  (= `cfg.tsconfig`) redirects `tailwindcss` → `.design-sync/tw-shim.css` (empty)
  so the JS bundle builds. Real styling ships via `cfg.cssEntry`, not these
  component CSS imports (which are all empty/trivial anyway).

## Known render warns (triaged, not new)
- `Button`, `CurrentModpackPage` — showed `[RENDER_BLANK]` **only before**
  authoring; Button now authored. CurrentModpackPage still floor-carded.
- `ApplyPage`, `SettingsPage` — `[RENDER_ERRORS]: invoke` (browser runtime has
  no `invoke`). **Non-blocking** — root renders fine (rich chrome); only live
  data is empty. Expected for any page that fetches on mount.

## Re-sync risks / watch-list
- **Purged Tailwind.** `quadrant-compiled.css` contains only the utility classes
  **used in `src`** (Tailwind v4 purges the rest). The palette enumerated in
  `conventions.md` is verified present, but the design agent using an *arbitrary*
  utility not in src (e.g. `bg-purple-500`) would get an unstyled result. To make
  the DS fully general, ship a non-purged/safelisted Tailwind build. Not done —
  ship-now decision. Revisit if designs come out partly unstyled.
- **Fidelity of Pages.** `CurrentModpackPage`, `SyncPage`, `ModInstallPage`,
  `SyncedModpack` render as floor cards (need `invoke` data). `Mod`,
  `Notifications` render but are data-driven — author previews with real props on
  a re-sync to lift them. These are the standing incremental-authoring offer.
- **Only `Button` has an authored preview** (`.design-sync/previews/Button.tsx`).
  The other 16 ship their auto-render/floor card. This was a "ship it now" run
  (user: "upload this shit"), not the full author-every-preview pass.
- **ShareSync context.** `SharePage`/`SyncPage`/`SyncedModpack` consume
  `ShareSyncPage`'s context — author their previews *inside* `ShareSyncPage`.

## Re-sync procedure
1. `node .design-sync/build-css.mjs`  (regenerate cssEntry + font)
2. re-copy staged scripts (`cp -r <skill>/… .ds-sync/`), then
   `node .ds-sync/resync.mjs --config .design-sync/config.json --node-modules ./node_modules --out ./ds-bundle --remote .design-sync/.cache/remote-sync.json`
