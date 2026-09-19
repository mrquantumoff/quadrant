use quadrant_core::{content::ContentLocation, mc_mod::ModType, ports::Shell};
use quadrant_host::QuadrantHost;
use tauri::{AppHandle, Manager};

use crate::tauri_adapter::TauriShell;

#[tauri::command]
pub fn get_installed_content(app: AppHandle) -> Result<Vec<ContentLocation>, tauri::Error> {
    app.state::<QuadrantHost>()
        .get_installed_content()
        .map_err(crate::command_error)
}

#[tauri::command]
pub async fn open_content_folder(
    location_id: String,
    mod_type: ModType,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    let folder = app
        .state::<QuadrantHost>()
        .content_folder(&location_id, mod_type)
        .map_err(crate::command_error)?;
    std::fs::create_dir_all(&folder).map_err(crate::command_error)?;
    TauriShell::new(app)
        .open_path(&folder)
        .map_err(crate::command_error)
}

#[tauri::command]
pub async fn copy_content(
    from_location: String,
    to_location: String,
    mod_type: ModType,
    file_names: Vec<String>,
    app: AppHandle,
) -> Result<usize, tauri::Error> {
    let host = app.state::<QuadrantHost>().inner().clone();
    // A pack can be hundreds of megabytes, so the copy runs off the async
    // runtime's worker threads.
    tauri::async_runtime::spawn_blocking(move || {
        host.copy_content(&from_location, &to_location, mod_type, file_names)
    })
    .await?
    .map_err(crate::command_error)
}

#[tauri::command]
pub async fn delete_content(
    location: String,
    mod_type: ModType,
    file_names: Vec<String>,
    app: AppHandle,
) -> Result<usize, tauri::Error> {
    let host = app.state::<QuadrantHost>().inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        host.delete_content(&location, mod_type, file_names)
    })
    .await?
    .map_err(crate::command_error)
}
