//! Account token helpers and Quadrant cloud entrypoints.

use std::env;

use crate::{Result, ports::SecretStore};

pub mod id;
pub mod quadrant_settings_sync;
pub mod quadrant_share;
pub mod quadrant_sync;

/// Returns the default backend base URL.
/// The compile-time default can be overridden by setting the `QUADRANT_API_BASE_URL`
/// environment variable at build time. Runtime overrides (via env var or CLI) take
/// precedence over this default.
const DEFAULT_BACKEND_BASE_URL: &str = "https://api.usequadrant.dev/api/v3";

fn qnt_base_url() -> &'static str {
    match option_env!("QUADRANT_API_BASE_URL").map(str::trim) {
        Some(value) if !value.is_empty() => value,
        _ => DEFAULT_BACKEND_BASE_URL,
    }
}
/// Stable keyring service name used by the current app.
pub const KEYRING_SERVICE: &str = "dev.mrquantumoff.mcmodpackmanager";

/// Resolves the backend base URL.
/// Precedence: CLI arg > `QUADRANT_API_BASE_URL` env var at runtime >
/// `QUADRANT_API_BASE_URL` env var at compile time > hardcoded default.
pub fn backend_base_url() -> String {
    env::var("QUADRANT_API_BASE_URL")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| qnt_base_url().to_string())
}

/// Persists a named secret in the host secret store.
pub fn set_secret(secret_store: &impl SecretStore, key: &str, value: &str) -> Result<()> {
    log::info!("Setting secret: {key}");
    secret_store.set_secret(key, value)
}

/// Reads the current account access token.
pub fn get_account_token(secret_store: &impl SecretStore) -> Result<String> {
    secret_store
        .get_secret("accountToken")?
        .ok_or_else(|| anyhow::anyhow!("No account token"))
}

/// Reads the current account refresh token.
pub fn get_refresh_token(secret_store: &impl SecretStore) -> Result<String> {
    secret_store
        .get_secret("refreshToken")?
        .ok_or_else(|| anyhow::anyhow!("No refresh token"))
}

/// Removes any persisted account and refresh tokens.
pub fn clear_account_token(secret_store: &impl SecretStore) -> Result<()> {
    log::info!("Clearing account and refresh tokens");
    let _ = secret_store.delete_secret("accountToken");
    let _ = secret_store.delete_secret("refreshToken");
    Ok(())
}
