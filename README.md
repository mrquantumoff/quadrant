<!-- @format -->

# Quadrant for Minecraft

> An easy way to manage your modpacks, written in React and Rust.

## Desktop Runtimes

Quadrant supports two desktop shells that share the same React renderer and backend contract:

- `Tauri`: the existing Rust desktop shell in `src-tauri/`
- `Electron`: the Node/Electron shell in `electron/`, backed by the Quadrant N-API bindings

Renderer code should go through the shared desktop API in `src/desktop/` so pages and components stay runtime-neutral.

## Development

- `bun run dev`: run the shared Vite renderer only
- `bun run dev:tauri`: run the Tauri desktop app
- `bun run dev:electron`: run the Electron desktop app
- `bun run build`: build the shared renderer
- `bun run build:tauri`: build the Tauri desktop app
- `bun run build:electron`: build the Electron desktop app
- `bun run package:electron`: package the Electron app
- `bun run build:napi`: rebuild the N-API addon used by Electron

ARM builds are supported through the same scripts by passing an architecture flag, for example `bun run package:electron -- --arch=arm64`.

## Backend Notes

- Tauri and Electron should keep the same backend command and event names.
- Tauri uses Rust commands/plugins directly.
- Electron uses `@quadrant/quadrant-node`, which loads `quadrant-napi` and forwards the same `QuadrantHost` contract.
- Both runtimes should keep using the same persisted files and keyring service names so users can switch between shells without migrating data.

See `docs/backend-compatibility.md` and `docs/desktop-backends.md` for the runtime contract and backend responsibilities.

### Installation guide:

##### The app is available on these stores:

##### Read the warnings before installation!

<a href="https://flathub.org/apps/details/dev.mrquantumoff.mcmodpackmanager">
    <img width="200" alt="Download on Flathub" src="https://dl.flathub.org/assets/badges/flathub-badge-i-en.svg"/>
</a>

<a href="https://apps.microsoft.com/detail/9nlt70m0tvd0">
        <img width="200" src="https://get.microsoft.com/images/en-us%20light.svg" alt="Download on Microsoft Store" />
</a>

##### The app is also packaged unofficially on [AUR](https://aur.archlinux.org/packages/quadrant-bin), but only Flathub, MS Store and Windows setup-based distributions are considered officialy supported, use other distribution methods at your risk.

#### OR

[Grab the latest build manually (Linux/Windows on x86_64/aarch64)](https://github.com/quadrantmc/quadrant/releases/latest)

### Working features

- Applying modpacks

- Clearing modpacks

- Installing mods and resourcepacks (not modpacks) from curseforge/modrinth

- Installing shaders from modrinth and curseforge

- Importing and exporting modpacks

- Updating mods from curseforge and modrinth

- Sharing modpacks with your friends

- Backing up modpacks to the cloud

- Collaborating on modpacks with your friends

> [!WARNING]
>
> #### If app fails to apply your modpacks after installation, delete your mods folder.
>
> #### The app relies on time being synced correctly on your machine. If you encounter issues with features like Quadrant ID / Quadrant Share / Quadrant Sync, make sure that your time is set correctly. If that doesn't help, check the [status](https://status.bultek.com.ua/status/main) page

> [!TIP]
>
> ##### If some of the app's functionality doesn't work properly on Windows, try enabling developer mode in the system settings and/or reinstalling the app from microsoft store.

> [!WARNING]
>
> #### Before requesting to the delete the data collected by the app, please be sure that you are using the latest version.
