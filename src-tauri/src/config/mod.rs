use tauri::AppHandle;
use quadrant_host::QuadrantHost;
use tauri::Manager;

pub use quadrant_core::config::{get_config_dir, get_mc_folder};

#[tauri::command]
pub fn get_minecraft_folder(app: AppHandle) -> Result<String, tauri::Error> {
    let path = app
        .state::<QuadrantHost>()
        .get_minecraft_folder()
        .map_err(tauri::Error::from)?;
    Ok(path.to_string_lossy().to_string())
}

#[tauri::command]
pub fn init_config(app: AppHandle) -> Result<(), tauri::Error> {
    app.state::<QuadrantHost>().init_config().map_err(tauri::Error::from)
}
