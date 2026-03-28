use tauri::{AppHandle, Manager};
use tokio::sync::Mutex;

pub use quadrant_core::account::quadrant_sync::{ModpackOwner, SyncedModpack};

use crate::{
    AppState,
    mc_mod::get_user_agent,
    modpacks::general::LocalModpack,
    tauri_adapter::{TauriSecretStore, mc_folder},
};

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
    let connection_id = {
        let state = app.state::<Mutex<AppState>>();
        let state = state.lock().await;
        state.notification_connection_id.clone()
    };

    let timestamp = quadrant_core::account::quadrant_sync::sync_modpack(
        &TauriSecretStore,
        &get_user_agent(),
        modpack.clone(),
        overwrite,
        Some(connection_id.as_str()),
    )
    .await
    .map_err(tauri::Error::from)?;

    let persisted_modpack_id = resolve_submitted_modpack_id(&modpack, timestamp).await?;
    persist_sync_metadata(&app, &modpack.name, timestamp as u64, persisted_modpack_id.as_deref())
        .map_err(tauri::Error::from)?;
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

async fn resolve_submitted_modpack_id(
    modpack: &LocalModpack,
    timestamp: i64,
) -> Result<Option<String>, tauri::Error> {
    let synced_modpacks = quadrant_core::account::quadrant_sync::get_synced_modpacks(
        &TauriSecretStore,
        &get_user_agent(),
        false,
        None,
    )
    .await
    .map_err(tauri::Error::from)?;

    let mut matching = synced_modpacks.into_iter().filter(|synced_modpack| {
        synced_modpack.name == modpack.name
            && synced_modpack.minecraft_version == modpack.version
            && synced_modpack.mod_loader == modpack.mod_loader
            && synced_modpack.last_synced == timestamp
    });

    let first = matching.next().map(|modpack| modpack.modpack_id);
    if matching.next().is_some() {
        return Ok(None);
    }

    Ok(first)
}

pub fn persist_sync_metadata(
    app: &AppHandle,
    modpack_name: &str,
    last_synced: u64,
    modpack_id: Option<&str>,
) -> Result<(), anyhow::Error> {
    let modpack_folder = mc_folder(app)?.join("modpacks").join(modpack_name);
    if !modpack_folder.exists() {
        return Ok(());
    }

    quadrant_core::modpacks::set_modpack_sync_date(
        &mc_folder(app)?,
        last_synced,
        modpack_name,
        modpack_id,
    )
}
