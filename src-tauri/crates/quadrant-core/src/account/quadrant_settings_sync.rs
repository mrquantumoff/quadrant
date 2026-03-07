//! Settings synchronization helpers for Quadrant cloud settings.

use std::collections::HashMap;

use anyhow::anyhow;
use chrono::DateTime;
use serde_json::{Value, json};

use crate::{
    Result,
    account::{QNT_BASE_URL, get_account_token},
    ports::{SecretStore, SettingsStore},
};

/// Setting keys that currently participate in cloud settings sync.
pub const SYNCED_KEYS: &[&str] = &[
    "collectUserData",
    "modrinth",
    "curseforge",
    "curseforgeUsage",
    "modrinthUsage",
    "hardwareId",
    "rssFeeds",
    "silentNews",
    "autoQuadrantSync",
    "showUnupgradeableMods",
    "lastPage",
    "extendedNavigation",
    "experimentalFeatures",
    "cacheKeepAlive",
    "clipIcons",
];

/// Pulls synced settings from the cloud into the local settings store.
pub async fn get_quadrant_settings(
    settings_store: &impl SettingsStore,
    secret_store: &impl SecretStore,
    user_agent: &str,
) -> Result<()> {
    let token = get_account_token(secret_store)?;
    let json = reqwest::Client::new()
        .get(format!("{}/quadrant/settings_sync/get", QNT_BASE_URL))
        .header("User-Agent", user_agent)
        .bearer_auth(token)
        .send()
        .await?
        .json::<serde_json::Value>()
        .await?;

    let last_settings_updated = DateTime::parse_from_rfc3339(
        &settings_store
            .get_string("lastSettingsUpdated")?
            .ok_or_else(|| anyhow!("lastSettingsUpdated missing"))?,
    )?;
    let sync_time = DateTime::parse_from_rfc3339(
        json["sync_date"]
            .as_str()
            .ok_or_else(|| anyhow!("sync_date missing"))?,
    )?;

    if last_settings_updated == sync_time {
        return Ok(());
    }
    if last_settings_updated > sync_time {
        return Err(anyhow!("Current settings are newer"));
    }

    if let Some(new_settings) = json["settings"].as_str() {
        let new_settings: Value = serde_json::from_str(new_settings)?;
        for (key, value) in new_settings
            .as_object()
            .ok_or_else(|| anyhow!("No valid settings"))?
        {
            settings_store.set_value(key, value.to_owned())?;
        }
        return Ok(());
    }

    Err(anyhow!("No valid settings"))
}

/// Pushes the current synced settings subset to the Quadrant backend.
pub async fn submit_quadrant_settings(
    settings_store: &impl SettingsStore,
    secret_store: &impl SecretStore,
    user_agent: &str,
) -> Result<()> {
    let token = get_account_token(secret_store)?;
    let entries = settings_store.entries()?;
    let new_sync_date = settings_store
        .get_string("lastSettingsUpdated")?
        .ok_or_else(|| anyhow!("lastSettingsUpdated missing"))?;
    let new_sync_date = DateTime::parse_from_rfc3339(&new_sync_date)?;

    let mut settings_map = HashMap::new();
    for (key, value) in entries {
        if SYNCED_KEYS.contains(&key.as_str()) {
            settings_map.insert(key, value);
        }
    }

    let response = reqwest::Client::new()
        .post(format!("{}/quadrant/settings_sync/submit", QNT_BASE_URL))
        .header("User-Agent", user_agent)
        .bearer_auth(token)
        .json(&json!({
            "settings": serde_json::to_string_pretty(&settings_map)?,
            "sync_date": new_sync_date.to_rfc3339(),
        }))
        .send()
        .await?;
    if !response.status().is_success() {
        return Err(anyhow!(response.text().await?));
    }
    Ok(())
}
