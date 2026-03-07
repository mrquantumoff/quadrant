use tauri::AppHandle;

use crate::{mc_mod::get_user_agent, tauri_adapter::TauriSettingsStore};

pub use quadrant_core::telemetry::AppInfo;

pub async fn get_telemetry_info(app: AppHandle) -> AppInfo {
    quadrant_core::telemetry::get_telemetry_info(
        &TauriSettingsStore::new(app.clone(), "config.json"),
        app.package_info().version.to_string(),
        tauri_plugin_os::platform().to_string().to_uppercase(),
    )
    .await
    .expect("failed to gather telemetry info")
}

#[tauri::command]
pub async fn send_telemetry(app: AppHandle) {
    let _ = quadrant_core::telemetry::send_telemetry(
        &TauriSettingsStore::new(app.clone(), "config.json"),
        &get_user_agent(),
        app.package_info().version.to_string(),
        tauri_plugin_os::platform().to_string().to_uppercase(),
        env!("QUADRANT_API_KEY"),
    )
    .await;
}

#[tauri::command]
pub async fn remove_telemetry(app: AppHandle) {
    let _ = quadrant_core::telemetry::remove_telemetry(
        &TauriSettingsStore::new(app, "config.json"),
        &get_user_agent(),
        env!("QUADRANT_API_KEY"),
    )
    .await;
}
