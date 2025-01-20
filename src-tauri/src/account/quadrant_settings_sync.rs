use std::collections::HashMap;

use crate::{mc_mod::get_user_agent, QNT_BASE_URL};
use anyhow::anyhow;
use chrono::prelude::*;
use serde_json::{json, Value};
use tauri::AppHandle;
use tauri_plugin_http::reqwest;
use tauri_plugin_store::StoreExt;

#[tauri::command]
pub async fn get_quadrant_settings(app: AppHandle) -> Result<(), tauri::Error> {
    let token = crate::account::get_account_token()?;
    let user_agent = get_user_agent();

    let client = reqwest::Client::new();
    let response = client
        .get(format!("{}/quadrant/settings_sync/get", QNT_BASE_URL))
        .header("User-Agent", user_agent)
        .bearer_auth(token)
        .send()
        .await
        .map_err(|e| anyhow!(e))?;

    let json = response
        .json::<serde_json::Value>()
        .await
        .map_err(|e| anyhow!(e))?;

    let config = app.store("config.json").map_err(|e| anyhow!(e))?;

    let last_settings_updated =
        DateTime::parse_from_rfc3339(config.get("lastSettingsUpdated").unwrap().as_str().unwrap())
            .map_err(|e| anyhow!(e))?;

    let sync_time = DateTime::parse_from_rfc3339(json["sync_date"].as_str().unwrap())
        .map_err(|e| anyhow!(e))?;

    if last_settings_updated == sync_time {
        return Ok(());
    }

    if last_settings_updated > sync_time {
        return Err(anyhow!("Current settings are newer").into());
    }

    let new_settings = json["settings"].as_str();
    match new_settings {
        Some(new_settings) => {
            let new_settings: Value = serde_json::from_str(new_settings)?;
            for (key, value) in new_settings.as_object().unwrap() {
                config.set(key, value.to_owned());
            }
            log::info!("Got newer settings");
            return Ok(());
        }
        None => {}
    }

    return Err(anyhow!("No valid settings").into());
}

#[tauri::command]
pub async fn submit_quadrant_settings(app: AppHandle) -> Result<(), tauri::Error> {
    let token = crate::account::get_account_token()?;
    let user_agent = get_user_agent();

    let client = reqwest::Client::new();

    let config = app.store("config.json").map_err(|e| anyhow!(e))?;

    let mut settings = config.entries();

    let new_sync_date = app.store("config.json").map_err(|e| anyhow!(e))?;
    let new_sync_date = new_sync_date.get("lastSettingsUpdated").unwrap();
    let new_sync_date = new_sync_date.as_str().unwrap();
    let new_sync_date = DateTime::parse_from_rfc3339(new_sync_date).map_err(|e| anyhow!(e))?;

    let synced_keys = vec![
        "collectUserData".to_string(),
        "modrinth".to_string(),
        "curseforge".to_string(),
        "curseforgeUsage".to_string(),
        "modrinthUsage".to_string(),
        "hardwareId".to_string(),
        "rssFeeds".to_string(),
        "silentNews".to_string(),
        "autoQuadrantSync".to_string(),
        "showUnupgradeableMods".to_string(),
        "lastPage".to_string(),
        "extendedNavigation".to_string(),
        "experimentalFeatures".to_string(),
        "cacheKeepAlive".to_string(),
        "clipIcons".to_string(),
    ];

    settings.retain_mut(|val| synced_keys.contains(&val.0));

    let mut settings_map = HashMap::new();

    for (key, value) in settings {
        settings_map.insert(key, value);
    }

    let json = json!({
        "settings": serde_json::to_string_pretty(&settings_map)?,
        "sync_date": new_sync_date.to_rfc3339()
    });

    let response = client
        .post(format!("{}/quadrant/settings_sync/submit", QNT_BASE_URL))
        .header("User-Agent", user_agent)
        .bearer_auth(token)
        .json(&json)
        .send()
        .await
        .map_err(|e| anyhow!(e))?;
    if !response.status().is_success() {
        let error_msg = response.text().await.map_err(|e| anyhow!(e))?;
        return Err(tauri::Error::from(anyhow!(error_msg)));
    }
    log::info!("Submitted settings sync");
    Ok(())
}
