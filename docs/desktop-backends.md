# Desktop Backends

Quadrant supports two desktop shells that share one renderer and one backend contract.

## Shared Architecture

- The React renderer lives in `src/`.
- Renderer code should import the shared desktop API from `src/desktop/` instead of importing Tauri or Electron APIs directly.
- Runtime selection happens in `src/desktop/runtime.ts`.
- The backend command surface is the `QuadrantHost` contract exposed by `quadrant-host`.

## Tauri Backend

- Shell entrypoint: `src-tauri/`
- Renderer bridge: `src/desktop/tauri.ts`
- Backend implementation: Rust commands and plugins inside the Tauri application

### Tauri Responsibilities

- window management
- updater integration
- dialogs, filesystem watching, clipboard, deep links, and HTTP
- forwarding renderer command payloads into Rust commands

## Electron Backend

- Shell entrypoint: `electron/main.mjs`
- Preload bridge: `electron/preload.mjs`
- Renderer bridge: `src/desktop/electron.ts`
- Backend implementation: `@quadrant/quadrant-node` -> `quadrant-napi` -> `quadrant-host`

### Electron Responsibilities

- creating the main window and tray
- updater orchestration with `electron-updater`
- store file persistence for `config.json` and `updateConfig.json`
- deep-link routing and OAuth callback server support
- forwarding `QuadrantHost` events back into the renderer

## Build Matrix

- `bun run dev:tauri` / `bun run build:tauri`
- `bun run dev:electron` / `bun run build:electron`
- `bun run build:napi` before packaged Electron builds when the native addon changes

## Compatibility Rules

- Renderer features should stay runtime-neutral.
- Command names and event names must remain stable across both backends.
- Persisted file names, app data layout, and keyring names must remain compatible.
- If a capability differs by shell, isolate the difference inside `src/desktop/*` or the shell entrypoint rather than branching inside feature components.
