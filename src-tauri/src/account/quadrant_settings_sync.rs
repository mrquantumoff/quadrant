use tauri::AppHandle;

use crate::{
    mc_mod::get_user_agent,
    tauri_adapter::{TauriSecretStore, TauriSettingsStore},
};

#[tauri::command]
pub async fn get_quadrant_settings(app: AppHandle) -> Result<(), tauri::Error> {
    quadrant_core::account::quadrant_settings_sync::get_quadrant_settings(
        &TauriSettingsStore::new(app, "config.json"),
        &TauriSecretStore,
        &get_user_agent(),
    )
    .await
    .map_err(tauri::Error::from)
}

#[tauri::command]
pub async fn submit_quadrant_settings(app: AppHandle) -> Result<(), tauri::Error> {
    quadrant_core::account::quadrant_settings_sync::submit_quadrant_settings(
        &TauriSettingsStore::new(app, "config.json"),
        &TauriSecretStore,
        &get_user_agent(),
    )
    .await
    .map_err(tauri::Error::from)
}
