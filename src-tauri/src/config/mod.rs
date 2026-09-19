use quadrant_host::QuadrantHost;
use tauri::AppHandle;
use tauri::Emitter;
use tauri::Manager;

pub use quadrant_core::config::{get_config_dir, get_mc_folder};

#[tauri::command]
pub fn get_minecraft_folder(app: AppHandle) -> Result<String, tauri::Error> {
    let path = app
        .state::<QuadrantHost>()
        .get_minecraft_folder()
        .map_err(crate::command_error)?;
    Ok(path.to_string_lossy().to_string())
}

#[tauri::command]
pub fn get_default_minecraft_folder() -> Result<String, tauri::Error> {
    let path = get_mc_folder()
        .map_err(crate::command_error)?
        .ok_or_else(|| {
            tauri::Error::from(anyhow::Error::from(
                quadrant_core::error::ErrorCode::NoMinecraftFolder,
            ))
        })?;
    Ok(path.to_string_lossy().to_string())
}

#[tauri::command]
pub fn init_config(app: AppHandle) -> Result<(), tauri::Error> {
    app.state::<QuadrantHost>()
        .init_config()
        .map_err(crate::command_error)
}

#[tauri::command]
pub fn get_config_value(
    app: AppHandle,
    key: String,
) -> Result<Option<serde_json::Value>, tauri::Error> {
    app.state::<QuadrantHost>()
        .get_config_value(&key)
        .map_err(crate::command_error)
}

#[tauri::command]
pub fn set_config_value(
    app: AppHandle,
    key: String,
    value: serde_json::Value,
) -> Result<(), tauri::Error> {
    app.state::<QuadrantHost>()
        .set_config_value(&key, value)
        .map_err(crate::command_error)?;
    app.emit("configChanged", key).map_err(tauri::Error::from)
}
