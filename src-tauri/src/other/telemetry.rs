use chrono::prelude::*;
use dotenvy_macro::dotenv;
use serde::{Deserialize, Serialize};
use tauri::AppHandle;
use tauri_plugin_http::reqwest;
use tauri_plugin_store::StoreExt;

use crate::{account::BASE_URL, mc_mod::get_user_agent};

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

pub async fn get_telemetry_info(app: AppHandle) -> AppInfo {
    let config = app.store("config.json").unwrap();
    let version = app.package_info().version.clone();
    let os = format!(
        "{} {}",
        tauri_plugin_os::platform(),
        tauri_plugin_os::version()
    );
    let hardware_id = config.get("hardwareId").unwrap().clone();
    let hardware_id = hardware_id.as_str().unwrap();

    let date_time = Utc::now();

    let country_info = reqwest::Client::new()
        .get("https://ipinfo.io/json")
        .send()
        .await
        .unwrap()
        .json::<MyIPResponse>()
        .await
        .unwrap();
    let country = country_info.country;

    let modrinth_usage = config
        .get("modrinthUsage")
        .unwrap()
        .as_i64()
        .unwrap_or_else(|| 0);
    let curseforge_usage = config
        .get("curseforgeUsage")
        .unwrap()
        .as_i64()
        .unwrap_or_else(|| 0);

    let res = AppInfo {
        version: version.to_string(),
        os,
        modrinth_usage,
        curseforge_usage,
        reference_file_usage: 0,
        manual_input_usage: 0,
        hardware_id: hardware_id.to_string(),
        date: date_time,
        country,
    };
    log::info!("Telemetry info: {:?}", res);
    res
}

#[tauri::command]
pub async fn send_telemetry(app: AppHandle) {
    let store = app.store("config.json").unwrap();
    if !store
        .get("collectUserData")
        .unwrap()
        .as_bool()
        .unwrap_or(true)
    {
        return;
    };
    let info = get_telemetry_info(app).await;
    let client = reqwest::Client::new();
    let request = client
        .post(format!("{}/quadrant/usage/submit", BASE_URL))
        .json(&info)
        .header("Authorization", dotenv!("QUADRANT_API_KEY"))
        .header("User-Agent", get_user_agent())
        .send()
        .await
        .unwrap();
    log::info!("Telemetry sent: {:?}", request);
}

#[tauri::command]
pub async fn remove_telemetry(app: AppHandle) {
    let store = app.store("config.json").unwrap();
    let hardware_id = store.get("hardwareId").unwrap();
    let hardware_id = hardware_id.as_str().unwrap();
    let client = reqwest::Client::new();
    let request = client
        .delete(format!("{}/quadrant/usage/delete", BASE_URL))
        .header("Authorization", dotenv!("QUADRANT_API_KEY"))
        .header("User-Agent", get_user_agent())
        .query(&[("hardware_id", hardware_id)])
        .send()
        .await
        .unwrap();
    log::info!("Telemetry sent: {:?}", request);
}
