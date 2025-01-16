use std::path::PathBuf;

use chrono::{Days, Utc};
use tauri::AppHandle;
use tauri_plugin_store::StoreExt;
use uuid::Uuid;

pub fn get_config_dir() -> Result<Option<PathBuf>, anyhow::Error> {
    #[cfg(target_os = "windows")]
    {
        let resolver = dirs::config_dir();
        Ok(resolver)
    }
    #[cfg(target_os = "macos")]
    {
        let resolver = dirs::config_dir();
        Ok(resolver)
    }
    #[cfg(target_os = "linux")]
    {
        let resolver = dirs::home_dir_dir();
        Ok(resolver)
    }
}
pub fn get_mc_folder() -> Result<Option<PathBuf>, anyhow::Error> {
    let mut path = get_config_dir()?;
    if path.is_none() {
        path = Some(PathBuf::from(".minecraft"));
    }
    let mut path = path.unwrap();
    path.push(".minecraft");
    Ok(Some(path))
}

#[tauri::command]
pub fn get_minecraft_folder() -> Result<String, tauri::Error> {
    let path = get_mc_folder().map_err(|e| tauri::Error::from(e))?.unwrap();
    Ok(path.to_str().unwrap().to_string())
}

#[tauri::command]
pub fn init_config(app: AppHandle) -> Result<(), tauri::Error> {
    let store = app.store("config.json").map_err(anyhow::Error::from)?;

    if store.get("clipIcons").is_none() {
        store.set("clipIcons", true);
    }

    if store.get("lastRSSfetched").is_none() {
        let fourteen_days_ago = Utc::now().checked_sub_days(Days::new(14)).unwrap();
        let iso_string = fourteen_days_ago.to_rfc3339();
        store.set("lastRSSfetched", iso_string);
    }

    if store.get("curseforge").is_none() {
        store.set("curseforge", true);
    }

    if store.get("modrinth").is_none() {
        store.set("modrinth", true);
    }

    if store.get("curseforgeUsage").is_none() {
        store.set("curseforgeUsage", 0);
    }

    if store.get("modrinthUsage").is_none() {
        store.set("modrinthUsage", 0);
    }

    if store.get("devMode").is_none() {
        store.set("devMode", false);
    }

    if store.get("hardwareId").is_none() {
        let uuid = Uuid::now_v7();
        store.set("hardwareId", uuid.to_string());
    }

    if store.get("rssFeeds").is_none() {
        store.set("rssFeeds", true);
    }

    if store.get("silentNews").is_none() {
        store.set("silentNews", false);
    }

    if store.get("autoQuadrantSync").is_none() {
        store.set("autoQuadrantSync", true);
    }

    if store.get("showUnupgradeableMods").is_none() {
        store.set("showUnupgradeableMods", false);
    }

    if store.get("lastPage").is_none() {
        store.set("lastPage", 0);
    }

    if store.get("extendedNavigation").is_none() {
        store.set("extendedNavigation", false);
    }

    if store.get("experimentalFeatures").is_none() {
        store.set("experimentalFeatures", false);
    }

    if store.get("dontShowUserDataRecommendation").is_none() {
        store.set("dontShowUserDataRecommendation", false);
    }

    if store.get("cacheKeepAlive").is_none()
        || !store.get("cacheKeepAlive").map_or(false, |v| v.is_number())
    {
        store.set("cacheKeepAlive", 30);
    }

    if store.get("syncSettings").is_none() {
        store.set("syncSettings", true);
    }

    if store.get("lastSettingsUpdated").is_none() {
        let now = Utc::now();
        let iso_string = now.to_rfc3339();
        store.set("lastSettingsUpdated", iso_string);
    }
    if store.get("mcFolder").is_none() {
        store.set(
            "mcFolder",
            get_mc_folder().unwrap().unwrap().to_str().unwrap(),
        );
    }
    if store.get("collectUserData").is_none() {
        // Auto enable telemetry on macOS and Windows
        #[cfg(target_os = "macos")]
        {
            store.set("collectUserData", true);
        }
        #[cfg(target_os = "windows")]
        {
            store.set("collectUserData", true);
        }
        #[cfg(target_os = "linux")]
        {
            store.set("collectUserData", false);
        }
    }
    Ok(())
}
