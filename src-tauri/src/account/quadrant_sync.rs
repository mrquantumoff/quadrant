use std::path::Path;

use anyhow::anyhow;
use serde_json::json;
use tauri::AppHandle;
use tauri_plugin_store::StoreExt;

pub use quadrant_core::account::quadrant_sync::{ModpackOwner, SyncedModpack};

use crate::{mc_mod::get_user_agent, tauri_adapter::TauriSecretStore};

#[tauri::command]
pub async fn get_synced_modpacks(
    show_owners: bool,
    modpack_id: Option<String>,
) -> Result<Vec<SyncedModpack>, tauri::Error> {
    quadrant_core::account::quadrant_sync::get_synced_modpacks(
        &TauriSecretStore,
        &get_user_agent(),
        show_owners,
        modpack_id,
    )
    .await
    .map_err(tauri::Error::from)
}

#[tauri::command]
pub async fn kick_member(modpack_id: String, username: String) -> Result<(), tauri::Error> {
    quadrant_core::account::quadrant_sync::kick_member(
        &TauriSecretStore,
        &get_user_agent(),
        modpack_id,
        username,
    )
    .await
    .map_err(tauri::Error::from)
}

#[tauri::command]
pub async fn invite_member(
    modpack_id: String,
    username: String,
    admin: bool,
) -> Result<(), tauri::Error> {
    quadrant_core::account::quadrant_sync::invite_member(
        &TauriSecretStore,
        &get_user_agent(),
        modpack_id,
        username,
        admin,
    )
    .await
    .map_err(tauri::Error::from)
}

#[tauri::command]
pub async fn delete_synced_modpack(modpack_id: String) -> Result<(), tauri::Error> {
    quadrant_core::account::quadrant_sync::delete_synced_modpack(
        &TauriSecretStore,
        &get_user_agent(),
        modpack_id,
    )
    .await
    .map_err(tauri::Error::from)
}

#[tauri::command]
pub async fn sync_modpack(
    modpack: crate::modpacks::general::LocalModpack,
    overwrite: bool,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    let timestamp = quadrant_core::account::quadrant_sync::sync_modpack(
        &TauriSecretStore,
        &get_user_agent(),
        modpack.clone(),
        overwrite,
    )
    .await
    .map_err(tauri::Error::from)?;

    let config = app.store("config.json").map_err(|e| anyhow!(e))?;
    let binding = config.get("mcFolder").unwrap();
    let mc_folder = binding.as_str().unwrap();
    let modpack_folder = Path::new(mc_folder).join("modpacks").join(&modpack.name);
    if !modpack_folder.exists() {
        return Ok(());
    }
    std::fs::write(
        modpack_folder.join("quadrantSync.json"),
        serde_json::to_string_pretty(&json!({ "last_synced": timestamp }))?,
    )?;
    Ok(())
}

#[tauri::command]
pub async fn answer_invite(
    modpack_id: String,
    notification_id: String,
    answer: bool,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    quadrant_core::account::quadrant_sync::answer_invite(
        &TauriSecretStore,
        &get_user_agent(),
        modpack_id,
        answer,
    )
    .await
    .map_err(tauri::Error::from)?;
    super::id::read_notification(notification_id, app).await
}
