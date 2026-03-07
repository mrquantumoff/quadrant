# Quadrant Core Architecture

## Purpose

`quadrant-core` is the backend library for Quadrant. It is designed to hold reusable backend logic while the host application owns:

- transport
- UI
- desktop integrations
- runtime orchestration

The current Tauri app is one host implementation. The same crate can be embedded by another Rust desktop shell, a CLI, or a future service process.

For the higher-level docs index, see:

- [quadrant-core.md](./quadrant-core.md)

## Layering

The intended layering is:

1. `quadrant-core`
   Contains domain models, filesystem logic, HTTP logic, cache logic, sync/share logic, and typed events.
2. Host adapter
   Implements persistence, secrets, events, and shell/platform features.
3. Frontend transport
   Exposes host operations to a UI through commands, IPC, HTTP, or FFI.
4. Frontend
   Calls transport APIs and renders the UI.

## Core Modules

### `config`

Responsibilities:

- resolve config and Minecraft directories
- define app defaults
- populate missing config keys

Important entrypoints:

- `get_config_dir`
- `get_mc_folder`
- `default_app_config`
- `ensure_default_app_config`

### `models`

Shared serialization-friendly types for the rest of the crate.

Examples:

- `ModSource`
- `InstalledMod`
- `ModLoader`
- `InstalledModpack`
- `LocalModpack`
- `Article`

### `events`

Defines typed progress and refresh events emitted by backend operations.

The host maps these to whatever frontend event system it uses.

### `ports`

Defines host-supplied interfaces:

- `SettingsStore`
- `SecretStore`
- `EventSink`
- `Shell`
- `Notifier`
- `RuntimeState`

Not every extracted service currently uses every trait. The trait set is intentionally broader so the host boundary is explicit.

### `modpacks`

Owns local modpack filesystem behavior:

- listing modpacks
- applying modpacks
- creating/updating/deleting modpacks
- registering/removing mods from a modpack
- syncing local sync metadata
- downloading and installing modpack contents
- exporting modpacks to zip

### `mc_mod`

Owns mod-provider and mod-install behavior:

- Minecraft version fetch
- search across providers
- provider-specific mod fetches
- update checks
- remote file download
- install into modpacks/resourcepacks/shaderpacks
- cache handling
- mod identification

Submodules:

- `cache`
- `modrinth`
- `curseforge`
- `curseforge_fingerprint`

### `account`

Owns account and cloud features:

- token storage contract helpers
- OAuth token exchange and refresh
- account info and notification state fetch
- synced modpack APIs
- share APIs
- settings sync APIs

Submodules:

- `id`
- `quadrant_sync`
- `quadrant_share`
- `quadrant_settings_sync`

### `rss`

Fetches the Quadrant news feed and returns typed `Article` values.

### `telemetry`

Builds telemetry payloads and sends or removes telemetry records.

## Host Boundary

The host must provide:

### Persistent settings

Needed for:

- config defaults
- provider preferences
- telemetry flags
- Minecraft folder path
- settings sync state

### Secrets

Needed for:

- account token
- refresh token

### Event transport

Needed for:

- download progress
- install progress
- export progress
- refresh notifications
- login refresh triggers

## Service Shape

The crate is organized by capability rather than by frontend command surface.

In practice, most hosts expose these capabilities as a backend service layer:

- settings/config bootstrap
- modpack management
- mod catalog and install operations
- account and cloud operations
- content/news fetching
- telemetry submission

That service layer is where the host should:

- translate transport payloads into Rust types
- map host errors into frontend-safe responses
- perform authorization and shell-specific checks
- convert `BackendEvent` into frontend event names

The current Tauri app follows this shape through thin wrapper commands and the adapter in [src-tauri/src/tauri_adapter.rs](Q:/quadrant/src-tauri/src/tauri_adapter.rs).

## What Still Belongs Outside Core

Even after extraction, these are host concerns:

- window management
- tray behavior
- updater lifecycle
- deep-link registration
- clipboard writes
- native dialogs
- native notifications
- process lifecycle
- frontend command transport

## Current Host: Tauri

The current Tauri host provides the adapter implementation in:

- [src-tauri/src/tauri_adapter.rs](Q:/quadrant/src-tauri/src/tauri_adapter.rs)

That file maps Tauri store, keyring, event emission, notifications, dialogs, and runtime state into the `quadrant-core` traits.

## Stability Rules

The extracted backend still preserves the current app contract documented in:

- [backend-compatibility.md](./backend-compatibility.md)

The practical meaning is:

- frontend command names remain unchanged
- event names remain unchanged
- config keys remain unchanged
- on-disk modpack layout remains unchanged

## Recommended Future Shape

If a non-Tauri frontend is added, the cleanest structure is:

1. Keep `quadrant-core` as the domain/backend library.
2. Add a host process that implements the ports.
3. Add a transport layer that exposes stable frontend operations.
4. Make the frontend depend only on that transport layer, not directly on Tauri APIs.

## Deployment Models

### In-process desktop host

This is the lowest-friction option. The host and backend run in the same process, and the frontend communicates with host commands directly.

### Out-of-process local backend

This is the cleanest option for a non-Rust frontend. A local service embeds `quadrant-core`, and the frontend talks to it over HTTP, JSON-RPC, or another IPC mechanism.

### Shared backend across multiple shells

If Quadrant later needs multiple frontends, `quadrant-core` should remain the shared source of truth while each shell keeps only transport and platform-specific behavior.
