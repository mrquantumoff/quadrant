You can develop the Quadrant Next client by:

- Installing the needed dependencies for [Tauri](https://tauri.app/start/prerequisites/) and [Rust](https://www.rust-lang.org/). If you're on Linux, you'll also need libsecret-1-dev.
- Then install Node.js and pnpm and run `pnpm install` in the root directory of the project.
- After that in order to run the app without any of the proprietary features, you can run `pnpm tauri dev -- --no-default-features`.
