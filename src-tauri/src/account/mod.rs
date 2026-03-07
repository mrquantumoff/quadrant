pub mod id;
pub mod quadrant_settings_sync;
pub mod quadrant_share;
pub mod quadrant_sync;

use crate::tauri_adapter::TauriSecretStore;

#[tauri::command]
pub fn set_secret(key: String, value: String) -> Result<(), tauri::Error> {
    quadrant_core::account::set_secret(&TauriSecretStore, &key, &value).map_err(tauri::Error::from)
}

pub fn get_account_token() -> Result<String, anyhow::Error> {
    quadrant_core::account::get_account_token(&TauriSecretStore)
}

pub fn get_refresh_token() -> Result<String, anyhow::Error> {
    quadrant_core::account::get_refresh_token(&TauriSecretStore)
}

#[tauri::command]
pub fn clear_account_token() -> Result<(), tauri::Error> {
    quadrant_core::account::clear_account_token(&TauriSecretStore).map_err(tauri::Error::from)
}
