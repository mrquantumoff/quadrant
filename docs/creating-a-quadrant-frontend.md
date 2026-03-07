# Creating a Quadrant Frontend

This guide explains how to build a frontend for Quadrant now that the backend logic lives in `quadrant-core`.

Use this with:

- [quadrant-core.md](./quadrant-core.md)
- [quadrant-core-architecture.md](./quadrant-core-architecture.md)
- [quadrant-core-api-reference.md](./quadrant-core-api-reference.md)
- [backend-compatibility.md](./backend-compatibility.md)

## Start With The Correct Mental Model

`quadrant-core` is a Rust backend library, not a frontend SDK.

A Quadrant frontend needs three layers:

1. frontend UI
2. frontend transport/client layer
3. backend host built on top of `quadrant-core`

If your frontend is not written in Rust, you still need a host process or transport bridge.

## Choose A Frontend Architecture

There are three realistic options.

## Option 1: Rust Desktop Host With Embedded UI

Examples:

- Tauri
- Wry
- egui with native Rust UI
- a custom desktop shell

This is the closest to the current app.

Recommended when:

- you want native filesystem access
- you want direct embedding of `quadrant-core`
- you want low latency and simple deployment

Structure:

- UI calls host commands
- host commands call `quadrant-core`
- host maps `BackendEvent` back to the UI

## Option 2: Local Service + Any Frontend

Examples:

- Electron plus local Rust service
- browser UI plus local HTTP or IPC service
- mobile or web shell plus background Rust process

Recommended when:

- the frontend stack is not Rust-native
- you want to reuse the same backend process across multiple shells

Structure:

- frontend talks to a local HTTP or IPC service
- service embeds `quadrant-core`
- service implements the `ports` traits

## Option 3: FFI Bridge

Examples:

- C ABI
- UniFFI
- Node native addon

Recommended when:

- you need a very tight embedding model
- you control both sides of the integration

This is more work than a local service and is not provided by the repo today.

## Recommended Architecture For A New Frontend

Unless you have a strong reason otherwise:

- keep `quadrant-core` embedded in a Rust host
- define a small transport layer for the frontend
- do not let the frontend call Tauri-specific APIs directly

That gives you:

- a stable frontend contract
- reusable backend logic
- the ability to replace the shell later without rewriting the backend

## The Host/Frontend Split

Keep this boundary strict:

- the host owns persistence, file access, secret storage, network calls through `quadrant-core`, and event translation
- the frontend owns rendering, view state, optimistic UI behavior, and user interaction flows

Do not let UI components call shell APIs directly. Put every backend interaction behind a frontend client interface.

## What Your Host Must Implement

At minimum:

### `SettingsStore`

Needed for:

- config bootstrap
- provider preferences
- Minecraft folder path
- usage counters
- settings sync
- telemetry opt-in

Implementation advice:

- back it with a JSON file or SQLite
- preserve existing key names if you want compatibility with the current app

### `SecretStore`

Needed for:

- `accountToken`
- `refreshToken`

Implementation advice:

- use the OS keychain when available
- avoid storing account tokens in plain config files

### `EventSink`

Needed for:

- mod download progress
- mod install progress
- modpack download progress
- export progress
- notification refresh events
- account refresh events

Implementation advice:

- map each `BackendEvent` to your frontend event system
- keep payload shapes stable if you want compatibility with the current frontend logic

## Optional Host Capabilities

These are still useful even though not all are deeply used by the extracted logic yet:

- `Shell`
- `Notifier`
- `RuntimeState`

You will almost certainly still need equivalents in a real host app.

## Host Boot Sequence

A new host should initialize in roughly this order:

1. construct settings, secrets, and event adapters
2. call `ensure_default_app_config`
3. resolve `mcFolder`
4. warm any caches you need
5. expose transport handlers for modpacks, mods, account, RSS, and telemetry
6. start optional background loops such as account refresh or synced modpack checks

## Frontend Features You Need To Cover

A complete Quadrant frontend usually needs screens and flows for:

- modpack listing and apply
- current modpack view
- mod search and detail
- install mod flow
- export and share flow
- account login and account status
- synced modpacks
- settings
- notifications and progress UI
- news feed

## Core Operations A Frontend Backend Client Should Expose

Your frontend should not call the raw `quadrant-core` functions directly. Wrap them in a backend client interface like this:

```ts
export interface QuadrantBackendClient {
  initConfig(): Promise<void>;
  getMinecraftFolder(): Promise<string>;

  getModpacks(hideFree: boolean): Promise<LocalModpack[]>;
  applyModpack(name: string): Promise<void>;
  createModpack(name: string, version: string, modLoader: ModLoader): Promise<void>;
  updateModpack(source: string, patch: Partial<LocalModpack>): Promise<void>;
  deleteModpack(name: string): Promise<void>;
  registerMod(mod: InstalledMod, modpack: string): Promise<void>;
  exportModpack(name: string): Promise<void>;

  getVersions(): Promise<MinecraftVersion[]>;
  searchMods(args: GlobalSearchModsArgs): Promise<Mod[]>;
  getMod(source: ModSource, args: GetModArgs): Promise<Mod>;
  installMod(...args: unknown[]): Promise<void>;
  installRemoteFile(...args: unknown[]): Promise<void>;
  identifyModpack(modpack: string): Promise<IdentifiedMod[]>;

  getAccountInfo(): Promise<AccountInfo>;
  oauth2Login(code: string, redirectUri: string): Promise<void>;
  getSyncedModpacks(showOwners: boolean, modpackId?: string): Promise<SyncedModpack[]>;
  syncModpack(modpack: LocalModpack, overwrite: boolean): Promise<void>;
  shareModpack(name: string): Promise<void>;

  getNews(): Promise<Article[]>;

  onBackendEvent(listener: (event: BackendEventEnvelope) => void): () => void;
}
```

The exact transport does not matter. The abstraction does.

## Transport Design Rules

If you are building a new transport layer, keep these rules:

- transport payloads should stay close to `quadrant-core` models, but not expose internal-only details casually
- long-running operations should emit progress over events, not only return a final response
- file-system or shell actions should be explicit commands, not hidden side effects
- authentication tokens should never flow through the frontend unless you intentionally design it that way

## Keep The Existing Contract If You Want Compatibility

If you want the new frontend to behave like the current app, preserve:

- existing command names
- existing event names
- existing config keys
- current modpack folder layout

The current frozen contract is documented in:

- [backend-compatibility.md](./backend-compatibility.md)

## Event Handling

Your frontend needs to respond to:

- `ModDownloadProgress`
- `ModInstallProgress`
- `ModpackDownloadProgress`
- `QuadrantExportProgress`
- `QuadrantShareSubmission`
- `RefreshNotifications`
- `RecheckAccountToken`

Practical recommendation:

- translate typed backend events into a frontend-safe event envelope
- keep one central event bus in the frontend
- store long-running progress in shared state, not only component-local state

Example event envelope:

```ts
type BackendEventEnvelope =
  | { type: "modDownloadProgress"; payload: { modId: string; progress: number } }
  | { type: "modInstallProgress"; payload: { modId: string; progress: number } }
  | { type: "modpackDownloadProgress"; payload: number }
  | { type: "quadrantExportProgress"; payload: number }
  | { type: "quadrantShareSubmission"; payload: unknown }
  | { type: "refreshNotifications"; payload: unknown }
  | { type: "recheckAccountToken" };
```

## Settings Strategy

Use the same keys unless you want to fork behavior.

Important keys:

- `mcFolder`
- `curseforge`
- `modrinth`
- `showUnupgradeableMods`
- `autoQuadrantSync`
- `syncSettings`
- `collectUserData`
- `cacheKeepAlive`
- `lastSettingsUpdated`

If you change these names, you are creating a new config contract and should do it intentionally.

## Account Strategy

The frontend should not manage OAuth tokens itself unless unavoidable.

Recommended:

- let the backend host own token exchange and refresh
- let the host persist tokens through `SecretStore`
- expose only high-level frontend actions such as `login`, `logout`, and `getAccountInfo`

## Suggested Backend Routes Or Commands

No single transport is mandated, but most frontends end up wanting a surface close to this:

- config bootstrap and settings read or write
- modpack list, apply, create, update, delete, register, and export
- mod search, details, install, update-check, and identify
- account login, status, logout, and notifications
- sync, share, and settings-sync operations
- RSS or news fetch
- telemetry opt-in submit or remove

This is intentionally close to the current frozen Tauri command contract because that preserves app behavior and migration safety.

## File Layout Compatibility

To interoperate with existing Quadrant data, preserve:

- `<mcFolder>/modpacks`
- `<mcFolder>/mods`
- `<mcFolder>/modpacks/<name>/modConfig.json`
- `<mcFolder>/modpacks/<name>/quadrantSync.json`

## Suggested Implementation Order

1. Implement `SettingsStore`, `SecretStore`, and `EventSink`.
2. Call `ensure_default_app_config`.
3. Expose modpack operations.
4. Expose mod search and install operations.
5. Add event forwarding for progress.
6. Expose account and sync operations.
7. Add news and telemetry.
8. Build the frontend UI on top of a backend client abstraction.

## Compatibility Checklist

If you want the frontend to interoperate with existing Quadrant installs, verify:

- config keys are unchanged
- keyring secret names are unchanged
- modpack manifests stay at `<mcFolder>/modpacks/<name>/modConfig.json`
- sync metadata stays at `<mcFolder>/modpacks/<name>/quadrantSync.json`
- event names are unchanged if you are reusing frontend logic
- command or route payloads preserve the same semantics

## Minimal Rust Host Skeleton

```rust
use quadrant_core::{
    Result,
    config::ensure_default_app_config,
    modpacks,
    ports::{EventSink, SecretStore, SettingsStore},
};

fn main() -> Result<()> {
    let settings = MySettingsStore::new()?;
    let _secrets = MySecretStore::new()?;
    let _events = MyEventSink::new();

    ensure_default_app_config(&settings)?;

    let mc_folder = std::path::PathBuf::from(
        settings.get_string("mcFolder")?.expect("mcFolder missing"),
    );
    let modpacks = modpacks::get_modpacks(&mc_folder, false)?;
    println!("Loaded {} modpacks", modpacks.len());

    Ok(())
}
```

## Common Mistakes

- coupling the frontend directly to Tauri APIs again
- exposing raw file paths and backend internals directly to UI components
- skipping `SettingsStore` and hardcoding config values
- storing account tokens in plain JSON
- inventing a transport contract before defining a backend client abstraction
- breaking the on-disk modpack format without a migration plan

## Practical Recommendation

For a brand new frontend, the safest route is:

1. keep `quadrant-core` in a Rust host
2. build a small backend client abstraction for the UI
3. preserve the current backend compatibility contract first
4. only then consider redesigning transport or storage contracts

## If You Want A Web Frontend

A browser-only frontend cannot use `quadrant-core` directly.

You need:

- a Rust backend process running locally or remotely
- an API layer on top of `quadrant-core`
- a browser client talking to that API

For a web build, the right pattern is service-first, not direct embedding.
