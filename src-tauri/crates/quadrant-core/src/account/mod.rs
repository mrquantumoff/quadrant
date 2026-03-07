use crate::{Result, ports::SecretStore};

pub mod id;
pub mod quadrant_settings_sync;
pub mod quadrant_share;
pub mod quadrant_sync;

pub const QNT_BASE_URL: &str = "https://api.mrquantumoff.dev/api/v3";
pub const KEYRING_SERVICE: &str = "dev.mrquantumoff.mcmodpackmanager";

pub fn set_secret(secret_store: &impl SecretStore, key: &str, value: &str) -> Result<()> {
    secret_store.set_secret(key, value)
}

pub fn get_account_token(secret_store: &impl SecretStore) -> Result<String> {
    secret_store
        .get_secret("accountToken")?
        .ok_or_else(|| anyhow::anyhow!("No account token"))
}

pub fn get_refresh_token(secret_store: &impl SecretStore) -> Result<String> {
    secret_store
        .get_secret("refreshToken")?
        .ok_or_else(|| anyhow::anyhow!("No refresh token"))
}

pub fn clear_account_token(secret_store: &impl SecretStore) -> Result<()> {
    let _ = secret_store.delete_secret("accountToken");
    let _ = secret_store.delete_secret("refreshToken");
    Ok(())
}
