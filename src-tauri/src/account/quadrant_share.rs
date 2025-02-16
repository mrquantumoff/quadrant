use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter};
use tauri_plugin_clipboard_manager::ClipboardExt;
use tauri_plugin_http::reqwest;
use tauri_plugin_store::StoreExt;

use crate::{
    mc_mod::get_user_agent,
    modpacks::general::{get_modpacks, InstalledModpack},
    QNT_BASE_URL,
};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]

pub struct QuadrantShareSubmissionResponse {
    pub code: i32,
    pub uses_left: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuadrantShareSubmission {
    pub hardware_id: String,
    pub mod_config: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuadrantShareResponse {
    pub code: i32,
    pub mod_config: String,
}

#[tauri::command]
pub async fn share_modpack(modpack_name: String, app: AppHandle) -> Result<(), tauri::Error> {
    let config = app.store("config.json").unwrap();
    let data_collection_enabled = config.get("collectUserData").unwrap();
    if !data_collection_enabled.as_bool().unwrap_or(false) {
        return Err(tauri::Error::from(anyhow::Error::msg("enableDataSharing")));
    }

    let modpack = get_modpacks(false, app.clone()).await;
    let modpack = modpack.iter().find(|m| m.name == modpack_name);
    if modpack.is_none() {
        return Err(tauri::Error::from(anyhow::Error::msg("Modpack not found")));
    }
    let modpack = modpack.unwrap();
    let shared_modpack = InstalledModpack::from(modpack.to_owned());

    share_modpack_raw(shared_modpack, app).await
}
#[tauri::command]
pub async fn share_modpack_raw(
    mod_config: InstalledModpack,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    let mut url = format!("{}/quadrant/share/submit", QNT_BASE_URL);
    let config = app.store("config.json").unwrap();
    let data_collection_enabled = config.get("collectUserData").unwrap();
    if !data_collection_enabled.as_bool().unwrap_or(false) {
        return Err(tauri::Error::from(anyhow::Error::msg("enableDataSharing")));
    }
    let token_res = crate::account::get_account_token();
    let client = reqwest::Client::new();
    let user_agent = get_user_agent();

    let token: Option<String> = match token_res {
        Ok(token) => Some(token),
        _ => None,
    };

    match &token {
        Some(_) => url = format!("{}/id", url),
        _ => {}
    }
    let mut request =
        client
            .post(&url)
            .header("User-Agent", user_agent)
            .body(serde_json::to_string_pretty(&QuadrantShareSubmission {
                hardware_id: config
                    .get("hardwareId")
                    .unwrap()
                    .as_str()
                    .unwrap()
                    .to_string(),
                mod_config: serde_json::to_string_pretty(&mod_config)?,
            })?);
    if let Some(token) = &token {
        request = request.bearer_auth(token);
    } else {
        request = request.header("Authorization", env!("QUADRANT_API_KEY"));
    }
    let response = request
        .send()
        .await
        .map_err(|e| tauri::Error::from(anyhow::Error::from(e)))?;
    log::info!("Response: {:?}", response);

    let res = response
        .json::<QuadrantShareSubmissionResponse>()
        .await
        .map_err(|e| tauri::Error::from(anyhow::Error::from(e)))?;

    app.emit("quadrantShareSubmission", &res)?;
    app.clipboard()
        .write_text(res.code.to_string())
        .map_err(|e| tauri::Error::from(anyhow::Error::from(e)))?;
    Ok(())
}

#[tauri::command]
pub async fn get_quadrant_share_modpack(code: String) -> Result<InstalledModpack, tauri::Error> {
    let url = format!("{}/quadrant/share/get", QNT_BASE_URL);
    let query = &[("code", code)];
    let client = reqwest::Client::new();
    let request = client
        .get(&url)
        .query(query.as_slice())
        .header("User-Agent", get_user_agent())
        .header("Authorization", env!("QUADRANT_API_KEY"))
        .send()
        .await
        .map_err(|e| tauri::Error::from(anyhow::Error::from(e)))?;
    let response = request
        .text()
        .await
        .map_err(|e| tauri::Error::from(anyhow::Error::from(e)))?;
    log::info!("Response: {:?}", response);

    let response: QuadrantShareResponse = serde_json::from_str(&response)?;

    let modpack: InstalledModpack = serde_json::from_str(&response.mod_config)?;
    Ok(modpack)
}
