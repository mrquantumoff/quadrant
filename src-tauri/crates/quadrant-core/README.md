# quadrant-core

`quadrant-core` is the Tauri-independent backend crate for Quadrant.

It contains the reusable backend logic that used to live directly inside the Tauri app:

- config defaults and Minecraft path resolution
- modpack discovery and filesystem operations
- mod search, install, update checks, cache management, and identification
- account, sync, share, and settings-sync HTTP logic
- RSS/news fetching
- telemetry payload construction and submission

It does not create windows, show dialogs, register deep links, manage trays, or talk to a webview directly. Those concerns stay in the host application.

## Documentation Map

Repository-level documentation lives in:

- `docs/quadrant-core.md`
- `docs/quadrant-core-architecture.md`
- `docs/quadrant-core-api-reference.md`
- `docs/creating-a-quadrant-frontend.md`
- `docs/backend-compatibility.md`

## What This Crate Is For

Use `quadrant-core` when you want to:

- embed Quadrant backend logic inside another Rust host
- build a non-Tauri desktop shell around the same backend
- create a CLI or background worker for Quadrant data and modpack operations
- define a backend service that another frontend can call

## What This Crate Is Not

`quadrant-core` is not a ready-made frontend API server.

Right now it is a Rust library with explicit host integration points. If your frontend is not written in Rust, you still need a transport layer such as:

- FFI bindings
- a local HTTP server
- JSON-RPC over stdio, sockets, or named pipes
- a desktop host process exposing a command bridge

## Module Map

- `config`: typed defaults and config bootstrapping
- `models`: shared data models used across services
- `events`: typed backend events for progress and frontend refreshes
- `ports`: host-provided abstractions such as settings, secrets, and events
- `modpacks`: local modpack filesystem logic
- `mc_mod`: mod provider integration, cache handling, install flows, and mod identification
- `account`: account, sync, share, and settings-sync logic
- `rss`: Quadrant news feed fetching
- `telemetry`: telemetry payload and submission logic

## Host Responsibilities

The host application is responsible for:

- providing `SettingsStore` for persisted config values
- providing `SecretStore` for account tokens and other secrets
- providing `EventSink` if it wants progress and refresh events
- choosing how results are exposed to the UI
- deciding how to schedule background work
- providing shell integrations such as dialogs, notifications, and clipboard if needed

The existing Tauri app does this through `src-tauri/src/tauri_adapter.rs`.

## Key Traits

### `SettingsStore`

Persistent key/value configuration.

Required methods:

- `get_value`
- `set_value`
- `entries`

Helper methods are already defined on the trait for:

- `get_bool`
- `get_i64`
- `get_string`
- `set_bool`
- `set_i64`
- `set_string`

### `SecretStore`

Secret persistence for things like:

- `accountToken`
- `refreshToken`

### `EventSink`

Receives typed backend events such as:

- `ModDownloadProgress`
- `ModInstallProgress`
- `ModpackDownloadProgress`
- `QuadrantExportProgress`
- `QuadrantShareSubmission`
- `RefreshNotifications`
- `RecheckAccountToken`

## Quick Start

Add the crate as a dependency:

```toml
[dependencies]
quadrant-core = { path = "src-tauri/crates/quadrant-core" }
serde_json = "1"
```

Implement the required ports:

```rust
use quadrant_core::{
    Result,
    events::BackendEvent,
    ports::{EventSink, SettingsStore},
};
use serde_json::Value;
use std::{cell::RefCell, collections::HashMap};

#[derive(Default)]
struct MemoryStore {
    values: RefCell<HashMap<String, Value>>,
}

impl SettingsStore for MemoryStore {
    fn get_value(&self, key: &str) -> Result<Option<Value>> {
        Ok(self.values.borrow().get(key).cloned())
    }

    fn set_value(&self, key: &str, value: Value) -> Result<()> {
        self.values.borrow_mut().insert(key.to_string(), value);
        Ok(())
    }

    fn entries(&self) -> Result<Vec<(String, Value)>> {
        Ok(self
            .values
            .borrow()
            .iter()
            .map(|(key, value)| (key.clone(), value.clone()))
            .collect())
    }
}

struct NoopEvents;

impl EventSink for NoopEvents {
    fn publish(&self, _event: BackendEvent) -> Result<()> {
        Ok(())
    }
}
```

Initialize config defaults:

```rust
use quadrant_core::config::ensure_default_app_config;

let store = MemoryStore::default();
ensure_default_app_config(&store)?;
```

Run core operations:

```rust
use quadrant_core::modpacks;
use std::path::PathBuf;

let mc_folder = PathBuf::from("C:/Users/you/AppData/Roaming/.minecraft");
let modpacks = modpacks::get_modpacks(&mc_folder, false)?;
```

From there, the usual integration order is:

1. Implement `SettingsStore`, `SecretStore`, and `EventSink`.
2. Run `ensure_default_app_config`.
3. Expose modpack flows.
4. Expose mod search and install flows.
5. Add account, sync, share, RSS, and telemetry surfaces.
6. Translate `BackendEvent` into your frontend event system.

## Smoke Example

There is a minimal host example at:

- `examples/smoke.rs`

Run it with:

```powershell
cargo run -p quadrant-core --example smoke -- <mc-folder> list
cargo run -p quadrant-core --example smoke -- <mc-folder> apply <modpack>
cargo run -p quadrant-core --example smoke -- <mc-folder> export <modpack>
```

## Features

- `curseforge`: enables CurseForge-specific provider logic under `mc_mod::curseforge`

Without this feature, Modrinth paths still work and CurseForge-specific operations return no results or errors depending on the call.

## Current Status

The crate is reusable, but it is still shaped by the existing app contract. In particular:

- some interfaces in `ports` are broader than the currently extracted services need
- frontend/webview transport is still implemented in the Tauri app, not here
- there is no official HTTP or IPC server layer in this crate

## Additional Docs

- [Quadrant Core Overview](../../../docs/quadrant-core.md)
- [Quadrant Core Architecture](../../../docs/quadrant-core-architecture.md)
- [Quadrant Core API Reference](../../../docs/quadrant-core-api-reference.md)
- [Creating a Quadrant Frontend](../../../docs/creating-a-quadrant-frontend.md)
