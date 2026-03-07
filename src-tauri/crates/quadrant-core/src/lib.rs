//! `quadrant-core` is the Tauri-independent backend crate for Quadrant.
//!
//! It contains the reusable backend and domain logic that can be embedded by
//! a desktop shell, a CLI, or a service process. The crate intentionally does
//! not own window management, tray behavior, dialogs, deep links, or frontend
//! transport. Those concerns remain in the host application.
//!
//! # Module Overview
//!
//! - [`config`]: config defaults, config bootstrap, and Minecraft path helpers
//! - [`models`]: shared serialization-friendly types
//! - [`events`]: typed backend event payloads
//! - [`ports`]: host-provided interfaces such as settings, secrets, and events
//! - [`modpacks`]: local modpack filesystem flows
//! - [`mc_mod`]: mod provider integration, install flows, cache, and identify
//! - [`account`]: account, sync, share, and settings-sync logic
//! - [`rss`]: Quadrant news feed fetching
//! - [`telemetry`]: telemetry payload construction and submission
//!
//! # Host Responsibilities
//!
//! A host embedding `quadrant-core` typically provides:
//!
//! - a [`ports::SettingsStore`] for persisted config values
//! - a [`ports::SecretStore`] for tokens and other secrets
//! - a [`ports::EventSink`] for progress and refresh events
//! - transport that exposes backend operations to a UI or caller
//! - optional shell integrations such as notifications, dialogs, or clipboard
//!
//! # Quick Start
//!
//! ```no_run
//! use quadrant_core::{
//!     Result,
//!     config::ensure_default_app_config,
//!     events::BackendEvent,
//!     ports::{EventSink, SettingsStore},
//! };
//! use serde_json::Value;
//! use std::{cell::RefCell, collections::HashMap};
//!
//! #[derive(Default)]
//! struct MemoryStore {
//!     values: RefCell<HashMap<String, Value>>,
//! }
//!
//! impl SettingsStore for MemoryStore {
//!     fn get_value(&self, key: &str) -> Result<Option<Value>> {
//!         Ok(self.values.borrow().get(key).cloned())
//!     }
//!
//!     fn set_value(&self, key: &str, value: Value) -> Result<()> {
//!         self.values.borrow_mut().insert(key.to_string(), value);
//!         Ok(())
//!     }
//!
//!     fn entries(&self) -> Result<Vec<(String, Value)>> {
//!         Ok(self
//!             .values
//!             .borrow()
//!             .iter()
//!             .map(|(key, value)| (key.clone(), value.clone()))
//!             .collect())
//!     }
//! }
//!
//! struct NoopEvents;
//!
//! impl EventSink for NoopEvents {
//!     fn publish(&self, _event: BackendEvent) -> Result<()> {
//!         Ok(())
//!     }
//! }
//!
//! let store = MemoryStore::default();
//! let _events = NoopEvents;
//! ensure_default_app_config(&store)?;
//! # Ok::<(), quadrant_core::Error>(())
//! ```
//!
//! See the repository docs for a fuller guide:
//!
//! - `docs/quadrant-core.md`
//! - `docs/quadrant-core-architecture.md`
//! - `docs/quadrant-core-api-reference.md`
//! - `docs/creating-a-quadrant-frontend.md`
pub mod account;
pub mod config;
pub mod events;
pub mod mc_mod;
pub mod models;
pub mod modpacks;
pub mod ports;
pub mod rss;
pub mod telemetry;

pub use anyhow::{Error, Result};
