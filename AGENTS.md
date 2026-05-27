# AGENTS.md

## Quick start
- **Package manager**: `bun@1.3.13` — never use npm, yarn, or pnpm. `bun install` in root.
- All TS/JSX files start with `/** @format */`; keep this header when creating new files.

## Commands

| Task | Command |
|------|---------|
| Renderer-only dev (Vite) | `bun run dev` |
| Tauri dev | `bun run dev:tauri` |
| Electron dev | `bun run dev:electron` |
| Build shared renderer | `bun run build` (runs `tsc && vite build`) |
| Build native N-API addon | `bun run build:napi` |
| Build Electron shell | `bun run build:electron` |
| Package Electron app | `bun run package:electron` |
| Lint | `bun run lint` |
| Tauri dev without proprietary features | `bun tauri dev -- -- --no-default-features` |
| Typecheck scripts | `bun run typecheck:scripts` |
| Typecheck Electron shell | `bun run typecheck:electron` |

## Architecture

- **Two desktop runtimes** share one React renderer (`src/`): **Tauri** (Rust, `src-tauri/`) and **Electron** (`electron/`).
- A **`RuntimeAdapter` interface** (`src/desktop/contract.ts`) abstracts the desktop shell from the renderer. Feature code **must** use `src/desktop/index.ts` exports (`invoke`, `listen`, `DesktopStore`, etc.) — never import Tauri or Electron APIs directly.
- Runtime detection is lazy (`src/desktop/runtime.ts`): Electron checked first (`window.quadrantElectron`), then Tauri globals, then browser fallback.
- **Rust workspace** (`src-tauri/Cargo.toml`): members are `crates/quadrant-core`, `crates/quadrant-host`, `crates/quadrant-napi`.
- **JS workspace**: `packages/quadrant-node` (`@quadrant/quadrant-node`) wraps the compiled N-API `.node` binary.

## Build order & gotchas

- **For Electron**: `build:napi` must run before `build:electron` or `dev:electron`. The native addon is compiled from `crates/quadrant-napi/` and output to `packages/quadrant-node/native/` (this directory is gitignored).
- **Compile-time credentials**: Rust uses `env!()` macros (`QUADRANT_API_KEY`, `QUADRANT_OAUTH2_CLIENT_ID`, `QUADRANT_OAUTH2_CLIENT_SECRET`, `ETERNAL_API_TOKEN`). These must be set in the environment before building, or the build will fail. CI provides them; locally you must supply them or build with `--no-default-features`.
- **Cargo features cascade**: `default` → `proprietary` → `telemetry` + `curseforge` + `quadrant_id`. Use `--no-default-features` for a build without CurseForge, telemetry, and Quadrant ID.
- Vite dev server is **fixed at port 1420** with `strictPort: true`. Vite ignores `src-tauri/**` for file watching.

## No tests
There are **no test suites** anywhere — no Jest, Vitest, `cargo test`, or CI test job. The only "verification" is building successfully. CI (`validate-desktop.yml`) just runs builds.

## Styling
- **Tailwind CSS v4** (via PostCSS, not the Tailwind CLI). Config is in `postcss.config.cjs`.
- ESM project (`"type": "module"`). `.cjs` files for CommonJS exceptions (PostCSS config, Tailwind config).

## Versioning
`YY.MM.REVISION` (e.g. `26.6.0-stable`). Tags use `v` prefix with suffix (`-stable`, `-flatpak`, `-msstore`). Prerelease tags skip the suffix.
