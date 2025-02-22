use anyhow::anyhow;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::path::Path;
use tauri::AppHandle;
use tauri_plugin_http::reqwest;
use tauri_plugin_store::StoreExt;

use crate::{
    account::get_account_token,
    mc_mod::get_user_agent,
    modpacks::general::{LocalModpack, ModLoader},
    QNT_BASE_URL,
};

use super::id::read_notification;

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ModpackOwner {
    pub username: String,
    pub admin: bool,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct SyncedModpack {
    pub name: String,
    pub minecraft_version: String,
    pub mod_loader: ModLoader,
    pub mods: String,
    pub owners: Vec<ModpackOwner>,
    pub last_synced: i64,
    pub modpack_id: String,
}

#[tauri::command]
pub async fn get_synced_modpacks(
    show_owners: bool,
    modpack_id: Option<String>,
) -> Result<Vec<SyncedModpack>, tauri::Error> {
    let mut query = vec![("show_owners", show_owners.to_string())];
    if let Some(modpack_id) = modpack_id {
        query.push(("modpack_id", modpack_id));
    }
    let url = format!("{}/quadrant/sync/get", QNT_BASE_URL);
    let client = reqwest::Client::new();
    let request = client
        .get(&url)
        .query(query.as_slice())
        .bearer_auth(get_account_token()?)
        .header("User-Agent", get_user_agent());
    let response = request.send().await.map_err(|e| anyhow::anyhow!(e))?;
    let body: Vec<SyncedModpack> = response.json().await.map_err(|e| anyhow::anyhow!(e))?;
    return Ok(body);
}

#[tauri::command]
pub async fn kick_member(modpack_id: String, username: String) -> Result<(), tauri::Error> {
    let url = format!("{}/quadrant/sync/kick", QNT_BASE_URL);
    let body = serde_json::json!({
        "modpack_id": modpack_id,
        "username": username});
    let client = reqwest::Client::new();
    let request = client
        .delete(url)
        .bearer_auth(get_account_token()?)
        .json(&body)
        .header("User-Agent", get_user_agent());
    let res = request.send().await.map_err(|e| anyhow::anyhow!(e))?;
    if res.status() != 200 {
        let reason = res.text().await.map_err(|e| anyhow::anyhow!(e))?;
        return Err(tauri::Error::from(anyhow::anyhow!(reason)));
    }
    Ok(())
}

#[tauri::command]
pub async fn invite_member(
    modpack_id: String,
    username: String,
    admin: bool,
) -> Result<(), tauri::Error> {
    let url = format!("{}/quadrant/sync/invite", QNT_BASE_URL);
    let body = serde_json::json!({
        "modpack_id": modpack_id,
        "username": username,
        "admin": admin});
    let client = reqwest::Client::new();
    let request = client
        .post(url)
        .bearer_auth(get_account_token()?)
        .json(&body)
        .header("User-Agent", get_user_agent());
    let res = request.send().await.map_err(|e| anyhow::anyhow!(e))?;
    if res.status() != 200 {
        let reason = res.text().await.map_err(|e| anyhow::anyhow!(e))?;
        return Err(tauri::Error::from(anyhow::anyhow!(reason)));
    }
    Ok(())
}

#[tauri::command]
pub async fn delete_synced_modpack(modpack_id: String) -> Result<(), tauri::Error> {
    let url = format!("{}/quadrant/sync/delete", QNT_BASE_URL);
    let body = serde_json::json!({
        "modpack_id": modpack_id,
    });
    let client = reqwest::Client::new();
    let request = client
        .delete(url)
        .bearer_auth(get_account_token()?)
        .json(&body)
        .header("User-Agent", get_user_agent());
    let res = request.send().await.map_err(|e| anyhow::anyhow!(e))?;
    if res.status() != 200 {
        let reason = res.text().await.map_err(|e| anyhow::anyhow!(e))?;
        return Err(tauri::Error::from(anyhow::anyhow!(reason)));
    }
    Ok(())
}

#[tauri::command]
pub async fn sync_modpack(
    modpack: LocalModpack,
    overwrite: bool,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    let config = app.store("config.json").map_err(|e| anyhow::anyhow!(e))?;

    let url = format!("{}/quadrant/sync/submit", QNT_BASE_URL);
    let timestamp = Utc::now().timestamp();
    let body = serde_json::json!({
        "name": modpack.name,
        "mc_version": modpack.version,
        "mod_loader": modpack.mod_loader.to_string(),
        "overwrite": overwrite,
        "mods": serde_json::to_string_pretty(&modpack.mods)?,
        "last_synced": &timestamp,
    });

    let client = reqwest::Client::new();
    let request = client
        .post(url)
        .bearer_auth(get_account_token()?)
        .json(&body)
        .header("User-Agent", get_user_agent());
    let res = request.send().await.map_err(|e| anyhow::anyhow!(e))?;
    if res.status() != 200 {
        let reason = res.text().await.map_err(|e| anyhow::anyhow!(e))?;
        log::error!("Failed to sync modpack: {}", reason);
        return Err(tauri::Error::from(anyhow::anyhow!(reason)));
    }

    let binding = config.get("mcFolder").unwrap();
    let mc_folder = binding.as_str().unwrap();
    let mc_folder = Path::new(&mc_folder);
    let modpacks_folder = mc_folder.join("modpacks");
    let modpack_folder = modpacks_folder.join(&modpack.name);
    if !modpack_folder.exists() {
        return Ok(());
    }
    let sync_file = modpack_folder.join("quadrantSync.json");
    std::fs::write(
        sync_file,
        serde_json::to_string_pretty(&json!({
            "last_synced": timestamp,
        }))?,
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
    let token = crate::account::get_account_token()?;
    let url = format!("{}/quadrant/sync/respond", QNT_BASE_URL);
    let client = reqwest::Client::new();
    let request = client
        .post(url)
        .bearer_auth(token)
        .json(&json!({
            "modpack_id": modpack_id,
            "accept": answer,
        }))
        .header("User-Agent", get_user_agent());
    let response = request.send().await.map_err(|e| anyhow!(e))?;
    if !response.status().is_success() {
        let body = response.text().await.map_err(|e| anyhow!(e))?;
        return Err(anyhow::Error::msg(body).into());
    }
    read_notification(notification_id, app).await
}
