# Quadrant Core

This is the entrypoint document for the extracted Quadrant backend.

`quadrant-core` is a Rust library that owns reusable backend logic while the host application owns transport, platform integrations, and UI orchestration.

Use this page as the index for the rest of the documentation set.

## What The Crate Owns

- config defaults and Minecraft path resolution
- modpack filesystem operations
- mod search, install, cache, and identify flows
- account, sync, share, and settings-sync HTTP logic
- RSS/news fetching
- telemetry payload and submission logic
- typed backend events

## What The Host Still Owns

- command transport such as IPC, HTTP, FFI, or desktop invoke handlers
- settings and secret persistence implementations
- event forwarding to the frontend
- native shell behaviors such as notifications, clipboard, dialogs, and open-path actions
- runtime scheduling for polling, background work, and update checks
- frontend state management and presentation

## Read This In Order

1. [Quadrant Core Architecture](./quadrant-core-architecture.md)
2. [Quadrant Core API Reference](./quadrant-core-api-reference.md)
3. [Creating a Quadrant Frontend](./creating-a-quadrant-frontend.md)
4. [Backend Compatibility Contract](./backend-compatibility.md)

## Typical Integration Flow

1. Add `quadrant-core` to a Rust host.
2. Implement `SettingsStore`, `SecretStore`, and `EventSink`.
3. Call `ensure_default_app_config`.
4. Expose the backend operations your frontend needs.
5. Translate `BackendEvent` into frontend-facing events.
6. Keep the storage keys and on-disk layout unchanged if you want compatibility with existing Quadrant data.

## Host Patterns

### Embedded desktop host

Best when the host itself is a Rust desktop shell.

Examples:

- Tauri
- Wry
- a custom desktop shell

### Local service host

Best when the frontend is not written in Rust.

Examples:

- browser UI plus local HTTP/IPC server
- multiple frontends sharing one backend process

### CLI or worker host

Best for testing, scripting, and operational tasks.

The repository already includes a minimal smoke example under `src-tauri/crates/quadrant-core/examples/smoke.rs`.

## Current Boundaries

The backend extraction is substantial, but `quadrant-core` is still a library, not a packaged service or frontend SDK.

That means:

- there is no official HTTP server in this crate
- there is no official FFI layer in this crate
- frontend contracts are still defined by the host
- the current React frontend in this repo still talks to Tauri directly
