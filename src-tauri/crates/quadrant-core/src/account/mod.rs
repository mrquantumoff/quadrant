//! Account token helpers and Quadrant cloud entrypoints.

use std::env;

use crate::{Result, ports::SecretStore};

pub mod id;
pub mod quadrant_settings_sync;
pub mod quadrant_share;
pub mod quadrant_sync;

/// Base URL for the Quadrant backend API.
pub const QNT_BASE_URL: &str = "https://api.usequadrant.dev/api/v3";
/// Stable keyring service name used by the current app.
pub const KEYRING_SERVICE: &str = "dev.mrquantumoff.mcmodpackmanager";

/// Resolves the backend base URL, preferring an explicit runtime override.
pub fn backend_base_url() -> String {
    env::var("QUADRANT_API_BASE_URL").unwrap_or_else(|_| QNT_BASE_URL.to_string())
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
