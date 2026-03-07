use chrono::prelude::*;
use serde::{Deserialize, Serialize};

use crate::{Result, account::QNT_BASE_URL, ports::SettingsStore};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppInfo {
    pub version: String,
    pub os: String,
    pub modrinth_usage: i64,
    pub curseforge_usage: i64,
    pub reference_file_usage: i64,
    pub manual_input_usage: i64,
    pub hardware_id: String,
    pub date: DateTime<Utc>,
    pub country: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct MyIPResponse {
    pub ip: String,
    pub country: String,
}

pub async fn get_telemetry_info(
    settings_store: &impl SettingsStore,
    version: String,
    os: String,
) -> Result<AppInfo> {
    let hardware_id = settings_store
        .get_string("hardwareId")?
        .unwrap_or_default();
    let date_time = Utc::now();

    let country_info = reqwest::Client::new()
        .get("https://ipinfo.io/json")
        .send()
        .await?
        .json::<MyIPResponse>()
        .await?;

    Ok(AppInfo {
        version,
        os,
        modrinth_usage: settings_store.get_i64("modrinthUsage")?.unwrap_or(0),
        curseforge_usage: settings_store.get_i64("curseforgeUsage")?.unwrap_or(0),
        reference_file_usage: 0,
        manual_input_usage: 0,
        hardware_id,
        date: date_time,
        country: country_info.country,
    })
}

pub async fn send_telemetry(
    settings_store: &impl SettingsStore,
    user_agent: &str,
    version: String,
    os: String,
    api_key: &str,
) -> Result<()> {
    if !settings_store.get_bool("collectUserData")?.unwrap_or(true) {
        return Ok(());
    }

    let info = get_telemetry_info(settings_store, version, os).await?;
    reqwest::Client::new()
        .post(format!("{}/quadrant/usage/submit", QNT_BASE_URL))
        .json(&info)
        .header("Authorization", api_key)
        .header("User-Agent", user_agent)
        .send()
        .await?;

    Ok(())
}

pub async fn remove_telemetry(
    settings_store: &impl SettingsStore,
    user_agent: &str,
    api_key: &str,
) -> Result<()> {
    let hardware_id = settings_store
        .get_string("hardwareId")?
        .unwrap_or_default();

    reqwest::Client::new()
        .delete(format!("{}/quadrant/usage/delete", QNT_BASE_URL))
        .header("Authorization", api_key)
        .header("User-Agent", user_agent)
        .query(&[("hardware_id", hardware_id)])
        .send()
        .await?;

    Ok(())
}
