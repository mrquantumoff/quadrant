use std::{collections::HashMap, path::PathBuf};

use crate::{
    account::{
        quadrant_settings_sync::{get_quadrant_settings, submit_quadrant_settings},
        quadrant_sync::{get_synced_modpacks, SyncedModpack},
    },
    mc_mod::get_user_agent,
    modpacks::general::{get_modpacks, install_modpack, InstalledModpack},
    AppState,
};
use chrono::prelude::*;
use dotenvy_macro::dotenv;
use serde::{Deserialize, Serialize};
use serde_json::json;
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_http::reqwest;
use tauri_plugin_notification::NotificationExt;
use tauri_plugin_store::StoreExt;
use tokio::sync::Mutex;

use super::{set_secret, BASE_URL};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccountInfo {
    pub id: String,
    pub name: String,
    pub email: String,
    pub quadrant_sync_limit: i32,
    pub quadrant_share_limit: i32,
    pub login: String,
    pub notifications: Vec<Notification>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Notification {
    pub notification_id: String,
    pub user_id: String,
    pub message: String,
    pub created_at: i64,
    pub read: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuth2Response {
    pub access_token: String,
    pub scope: String,
}

#[tauri::command]
pub async fn get_account_info() -> Result<AccountInfo, tauri::Error> {
    let token = crate::account::get_account_token();
    if token.is_err() {
        return Err(tauri::Error::from(anyhow::Error::from(
            token.err().unwrap(),
        )));
    }
    let token = token.unwrap();
    let client = reqwest::Client::new();
    let user_agent = get_user_agent();

    let url = format!("{}/account/info/get", BASE_URL);

    let request = client
        .get(&url)
        .header("User-Agent", user_agent)
        .bearer_auth(&token)
        .send()
        .await
        .map_err(|e| tauri::Error::from(anyhow::Error::from(e)))?;

    let response_raw = request
        .text()
        .await
        .map_err(|e| tauri::Error::from(anyhow::Error::from(e)))?;

    let response: AccountInfo = serde_json::from_str(&response_raw)?;

    log::info!("Got account info!");

    Ok(response)
}

#[tauri::command]
pub async fn oauth2_login(code: String, app: AppHandle) -> Result<(), tauri::Error> {
    let client = reqwest::Client::new();
    let user_agent = get_user_agent();
    let url = format!("{}/account/oauth2/token/access", BASE_URL);

    let mut body = HashMap::new();
    body.insert("client_id", dotenv!("QUADRANT_OAUTH2_CLIENT_ID"));
    body.insert("client_secret", dotenv!("QUADRANT_OAUTH2_CLIENT_SECRET"));
    body.insert("grant_type", "authorization_code");
    body.insert("code", &code);

    let request = client
        .post(url)
        .form(&body)
        .header("User-Agent", user_agent)
        .send();
    let response = request
        .await
        .map_err(|e| tauri::Error::from(anyhow::Error::from(e)))?;
    let res = response
        .json::<OAuth2Response>()
        .await
        .map_err(|e| tauri::Error::from(anyhow::Error::from(e)))?;
    if !res.scope.contains("user_data")
        || !res.scope.contains("quadrant_sync")
        || !res.scope.contains("notifications")
    {
        return Err(anyhow::Error::msg("Invalid scope").into());
    }
    set_secret("accountToken".to_string(), res.access_token)?;
    app.emit("recheckAccountToken", "")?;
    log::info!("OAuth2 Token saved, Quadrant ID saved.");
    Ok(())
}

#[tauri::command]
pub async fn read_notification(
    notification_id: String,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    let token = crate::account::get_account_token()?;
    let client = reqwest::Client::new();
    let user_agent = get_user_agent();
    let url = format!("{}/account/notifications/read", BASE_URL);
    let request = client
        .post(&url)
        .header("User-Agent", user_agent)
        .bearer_auth(&token)
        .json(&serde_json::json!({
            "notification_id": notification_id,
        }))
        .send()
        .await
        .map_err(|e| tauri::Error::from(anyhow::Error::from(e)))?;

    let response_raw = request.status();
    log::info!("Notification read: {}", &response_raw);
    if response_raw != 200 {
        let body = request.text().await.unwrap();
        return Err(anyhow::Error::msg(body).into());
    }
    app.emit(
        "refreshNotifications",
        get_account_info().await?.notifications,
    )?;
    Ok(())
}
pub async fn check_account_updates(app: AppHandle) -> Result<(), anyhow::Error> {
    let account_info = get_account_info().await;
    if account_info.is_err() {
        return Ok(());
    }
    let account_info = account_info.unwrap();
    app.emit("refreshNotifications", account_info.notifications)?;
    log::info!("Got new account info!");
    let config = app.store("config.json")?;
    let auto_quadrant_sync = config.get("autoQuadrantSync").unwrap().as_bool().unwrap();
    let auto_settings_sync = config.get("syncSettings").unwrap().as_bool().unwrap();
    let mc_folder = config.get("mcFolder").unwrap();
    let mc_folder = PathBuf::from(mc_folder.as_str().unwrap());
    let modpacks_folder = mc_folder.join("modpacks");

    if auto_quadrant_sync {
        let modpacks = get_modpacks(true, app.clone()).await;
        let synced_modpacks = get_synced_modpacks(false, None).await?;

        let state = app.state::<Mutex<AppState>>();
        for modpack in modpacks {
            if modpack.last_synced == 0 {
                continue;
            }

            // log::info!("Checking modpack: {}", modpack.name);
            let matching_modpacks: Vec<SyncedModpack> = synced_modpacks
                .iter()
                .filter(|m| &m.name == &modpack.name)
                .cloned()
                .collect();

            for matching_modpack in matching_modpacks {
                let mut state_mutex = state.lock().await;

                let cloud_sync_time = matching_modpack.last_synced;
                let local_sync_time = modpack.last_synced / 1000;

                let is_updated = state_mutex.updated_modpacks.contains(&modpack.name);
                let is_older = cloud_sync_time <= local_sync_time;

                // log::info!(
                //     "Checking if {} > {} ({}), while the modpack {} is updated =  {}",
                //     cloud_sync_time,
                //     local_sync_time,
                //     is_older,
                //     modpack.name,
                //     is_updated
                // );

                if is_older || is_updated {
                    drop(state_mutex);
                    continue;
                }
                state_mutex.updated_modpacks.push(modpack.name.clone());
                drop(state_mutex);

                // log::info!("Syncing modpack: {}", modpack.clone().name);
                app.notification()
                    .builder()
                    .title(modpack.clone().name)
                    .large_body(format!("{} | {}", modpack.name, modpack.version))
                    .body("🔃 Updating...")
                    .show()?;
                install_modpack(
                    InstalledModpack {
                        mod_loader: matching_modpack.mod_loader,
                        name: matching_modpack.name,
                        version: matching_modpack.minecraft_version,
                        mods: serde_json::from_str(&matching_modpack.mods)?,
                    },
                    app.clone(),
                )
                .await?;
                let sync_file = modpacks_folder
                    .join(&modpack.name)
                    .join("quadrantSync.json");
                let time = DateTime::from_timestamp(matching_modpack.last_synced, 0)
                    .unwrap()
                    .with_timezone(&Local);
                std::fs::write(
                    sync_file,
                    serde_json::to_string_pretty(&json!({
                        "last_synced": time.timestamp(),
                    }))?,
                )?;
                app.notification()
                    .builder()
                    .large_body(format!("{} | {}", modpack.name, modpack.version))
                    .title(modpack.clone().name)
                    .body("✅ Successfully updated!")
                    .show()?;
                let mut state_mutex = state.lock().await;

                state_mutex.updated_modpacks.retain(|m| m != &modpack.name);
                drop(state_mutex);
            }
        }
    }

    if auto_settings_sync {
        let res = get_quadrant_settings(app.clone()).await;
        match res {
            Ok(_) => {}
            Err(e) => {
                let err_msg = e.to_string();
                if err_msg == "Current settings are newer" {
                    submit_quadrant_settings(app.clone()).await?;
                }
            }
        }
    }

    Ok(())
}
