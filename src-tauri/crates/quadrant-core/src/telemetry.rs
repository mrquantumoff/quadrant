//! Telemetry payload construction and submission helpers.

use chrono::prelude::*;
use serde::{Deserialize, Serialize};

use crate::{Result, account::QNT_BASE_URL, ports::SettingsStore};

/// Telemetry payload submitted to the Quadrant backend.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppInfo {
    /// Current host application version.
    pub version: String,
    /// Current operating system label supplied by the host.
    pub os: String,
    /// Number of Modrinth-backed actions performed.
    pub modrinth_usage: i64,
    /// Number of CurseForge-backed actions performed.
    pub curseforge_usage: i64,
    /// Reference file usage counter.
    pub reference_file_usage: i64,
    /// Manual input usage counter.
    pub manual_input_usage: i64,
    /// Stable installation identifier.
    pub hardware_id: String,
    /// Submission timestamp.
    pub date: DateTime<Utc>,
    /// ISO country code inferred from the public IP lookup.
    pub country: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct MyIPResponse {
    pub ip: String,
    pub country: String,
}

/// Collects the current telemetry snapshot from settings and the host.
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

/// Sends telemetry data when collection is enabled in settings.
pub async fn send_telemetry(
    settings_store: &impl SettingsStore,
    user_agent: &str,
    version: String,
    os: String,
    api_key: &str,
) -> Result<()> {
    if !settings_store.get_bool("collectUserData")?.unwrap_or(true) {
        log::info!("Telemetry skipped: data collection is disabled");
        return Ok(());
    }

    log::info!("Sending telemetry for version {version} on {os}");
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

/// Deletes telemetry data for the current installation.
pub async fn remove_telemetry(
    settings_store: &impl SettingsStore,
    user_agent: &str,
    api_key: &str,
) -> Result<()> {
    log::info!("Removing telemetry data");
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
