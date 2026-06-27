<!-- @format -->

You can develop the Quadrant Next client by:

- Installing the needed dependencies for [Tauri](https://tauri.app/start/prerequisites/) and [Rust](https://www.rust-lang.org/). If you're on Linux, you'll also need libsecret-1-dev.
- Then install bun and run `bun install` in the root directory of the project.
- Renderer-only development remains available through `bun run dev`.
- Tauri development is available through `bun run dev:tauri`.
- To build the shared renderer only, run `bun run build`.
- To build the Tauri app without any of the proprietary features, run `bun tauri dev -- -- --no-default-features`.
