use tauri::AppHandle;

pub use quadrant_core::config::{get_config_dir, get_mc_folder};

use crate::tauri_adapter::TauriSettingsStore;

#[tauri::command]
pub fn get_minecraft_folder() -> Result<String, tauri::Error> {
    let path = get_mc_folder().map_err(tauri::Error::from)?.unwrap();
    Ok(path.to_string_lossy().to_string())
}

#[tauri::command]
pub fn init_config(app: AppHandle) -> Result<(), tauri::Error> {
    let store = TauriSettingsStore::new(app, "config.json");
    quadrant_core::config::ensure_default_app_config(&store).map_err(tauri::Error::from)
}
