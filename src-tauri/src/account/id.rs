use std::path::PathBuf;

use serde_json::json;
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_notification::NotificationExt;
use tauri_plugin_store::StoreExt;
use tokio::sync::Mutex;

use crate::{
    AppState,
    account::{
        quadrant_settings_sync::{get_quadrant_settings, submit_quadrant_settings},
        quadrant_sync::get_synced_modpacks,
    },
    mc_mod::get_user_agent,
    modpacks::general::{InstalledModpack, get_modpacks, install_modpack},
    tauri_adapter::TauriSecretStore,
};

pub use quadrant_core::account::id::{AccountInfo, Notification, OAuth2Response};

#[tauri::command]
pub async fn get_account_info() -> Result<AccountInfo, tauri::Error> {
    quadrant_core::account::id::get_account_info_with_refresh(
        &TauriSecretStore,
        &get_user_agent(),
        env!("QUADRANT_OAUTH2_CLIENT_ID"),
        env!("QUADRANT_OAUTH2_CLIENT_SECRET"),
    )
    .await
    .map_err(tauri::Error::from)
}

#[tauri::command]
pub async fn oauth2_login(
    code: String,
    redirect_uri: String,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    quadrant_core::account::id::oauth2_login(
        &TauriSecretStore,
        &get_user_agent(),
        env!("QUADRANT_OAUTH2_CLIENT_ID"),
        env!("QUADRANT_OAUTH2_CLIENT_SECRET"),
        code,
        redirect_uri,
    )
    .await
    .map_err(tauri::Error::from)?;
    app.emit("recheckAccountToken", "")?;
    Ok(())
}

#[tauri::command]
pub fn oauth2_client_id() -> String {
    env!("QUADRANT_OAUTH2_CLIENT_ID").to_string()
}

#[tauri::command]
pub async fn read_notification(
    notification_id: String,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    quadrant_core::account::id::read_notification(
        &TauriSecretStore,
        &get_user_agent(),
        notification_id,
    )
    .await
    .map_err(tauri::Error::from)?;
    app.emit(
        "refreshNotifications",
        get_account_info().await?.notifications,
    )?;
    Ok(())
}

pub async fn check_account_updates(app: AppHandle) -> Result<(), anyhow::Error> {
    let account_info = match quadrant_core::account::id::get_account_info_with_refresh(
        &TauriSecretStore,
        &get_user_agent(),
        env!("QUADRANT_OAUTH2_CLIENT_ID"),
        env!("QUADRANT_OAUTH2_CLIENT_SECRET"),
    )
    .await
    {
        Ok(info) => info,
        Err(_) => return Ok(()),
    };
    app.emit("refreshNotifications", account_info.notifications.clone())?;

    let config = app.store("config.json")?;
    let auto_quadrant_sync = config.get("autoQuadrantSync").unwrap().as_bool().unwrap();
    let auto_settings_sync = config.get("syncSettings").unwrap().as_bool().unwrap();
    let mc_folder = PathBuf::from(config.get("mcFolder").unwrap().as_str().unwrap());
    let modpacks_folder = mc_folder.join("modpacks");

    if auto_quadrant_sync {
        let modpacks = get_modpacks(true, app.clone()).await;
        let synced_modpacks = get_synced_modpacks(false, None).await?;
        let state = app.state::<Mutex<AppState>>();
        let currently_updated = {
            let state = state.lock().await;
            state.updated_modpacks.clone()
        };
        let pending = quadrant_core::account::id::determine_pending_modpack_updates(
            &modpacks,
            &synced_modpacks,
            &currently_updated,
        );

        for pending_update in pending {
            {
                let mut state_mutex = state.lock().await;
                if state_mutex
                    .updated_modpacks
                    .contains(&pending_update.local_name)
                {
                    continue;
                }
                state_mutex
                    .updated_modpacks
                    .push(pending_update.local_name.clone());
            }

            app.notification()
                .builder()
                .title(pending_update.local_name.clone())
                .large_body(format!(
                    "{} | {}",
                    pending_update.local_name, pending_update.local_version
                ))
                .body("Updating...")
                .show()?;

            install_modpack(
                InstalledModpack {
                    mod_loader: pending_update.synced_modpack.mod_loader,
                    name: pending_update.synced_modpack.name.clone(),
                    version: pending_update.synced_modpack.minecraft_version.clone(),
                    mods: serde_json::from_str(&pending_update.synced_modpack.mods)?,
                },
                app.clone(),
            )
            .await?;

            std::fs::write(
                modpacks_folder
                    .join(&pending_update.local_name)
                    .join("quadrantSync.json"),
                serde_json::to_string_pretty(&json!({
                    "last_synced": pending_update.synced_modpack.last_synced,
                }))?,
            )?;

            app.notification()
                .builder()
                .large_body(format!(
                    "{} | {}",
                    pending_update.local_name, pending_update.local_version
                ))
                .title(pending_update.local_name.clone())
                .body("Successfully updated!")
                .show()?;

            let mut state_mutex = state.lock().await;
            state_mutex
                .updated_modpacks
                .retain(|name| name != &pending_update.local_name);
        }
    }

    if auto_settings_sync {
        let res = get_quadrant_settings(app.clone()).await;
        if let Err(error) = res {
            if error.to_string() == "Current settings are newer" {
                submit_quadrant_settings(app.clone()).await?;
            }
        }
    }

    Ok(())
}
