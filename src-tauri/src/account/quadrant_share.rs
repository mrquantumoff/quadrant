use tauri::{AppHandle, Emitter};
use tauri_plugin_clipboard_manager::ClipboardExt;

pub use quadrant_core::account::quadrant_share::{
    QuadrantShareResponse, QuadrantShareSubmission, QuadrantShareSubmissionResponse,
};

use crate::{
    mc_mod::get_user_agent,
    modpacks::general::{InstalledModpack, get_modpacks},
    tauri_adapter::{TauriSecretStore, TauriSettingsStore},
};

#[tauri::command]
pub async fn share_modpack(modpack_name: String, app: AppHandle) -> Result<(), tauri::Error> {
    let modpacks = get_modpacks(false, app.clone()).await;
    let modpack = modpacks
        .iter()
        .find(|modpack| modpack.name == modpack_name)
        .ok_or_else(|| tauri::Error::from(anyhow::anyhow!("Modpack not found")))?;
    share_modpack_raw(InstalledModpack::from(modpack.to_owned()), app).await
}

#[tauri::command]
pub async fn share_modpack_raw(
    mod_config: InstalledModpack,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    let res = quadrant_core::account::quadrant_share::share_modpack_raw(
        &TauriSettingsStore::new(app.clone(), "config.json"),
        &TauriSecretStore,
        &get_user_agent(),
        mod_config,
        env!("QUADRANT_API_KEY"),
    )
    .await
    .map_err(tauri::Error::from)?;

    crate::other::telemetry::send_telemetry(app.clone()).await;
    app.emit("quadrantShareSubmission", &res)?;
    app.clipboard()
        .write_text(res.code.to_string())
        .map_err(|e| tauri::Error::from(anyhow::Error::from(e)))?;
    Ok(())
}

#[tauri::command]
pub async fn get_quadrant_share_modpack(code: String) -> Result<InstalledModpack, tauri::Error> {
    quadrant_core::account::quadrant_share::get_quadrant_share_modpack(
        &get_user_agent(),
        env!("QUADRANT_API_KEY"),
        code,
    )
    .await
    .map_err(tauri::Error::from)
}
