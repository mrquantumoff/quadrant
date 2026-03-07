use crate::{Result, ports::SettingsStore};
use chrono::{Days, Utc};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppConfig {
    pub clip_icons: bool,
    pub last_rss_fetched: String,
    pub curseforge: bool,
    pub modrinth: bool,
    pub curseforge_usage: i64,
    pub modrinth_usage: i64,
    pub dev_mode: bool,
    pub hardware_id: String,
    pub rss_feeds: bool,
    pub silent_news: bool,
    pub auto_quadrant_sync: bool,
    pub show_unupgradeable_mods: bool,
    pub last_page: i64,
    pub extended_navigation: bool,
    pub experimental_features: bool,
    pub dont_show_user_data_recommendation: bool,
    pub cache_keep_alive: i64,
    pub sync_settings: bool,
    pub last_settings_updated: String,
    pub mc_folder: String,
    pub collect_user_data: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateConfig {
    pub channel: String,
}

pub fn get_config_dir() -> Result<Option<PathBuf>> {
    #[cfg(any(target_os = "windows", target_os = "macos"))]
    {
        Ok(dirs::config_dir())
    }
    #[cfg(target_os = "linux")]
    {
        Ok(dirs::home_dir())
    }
}

pub fn get_mc_folder() -> Result<Option<PathBuf>> {
    let mut path = get_config_dir()?;
    if path.is_none() {
        path = Some(PathBuf::from(".minecraft"));
    }
    let mut path = path.expect("mc folder path should always resolve");
    path.push(".minecraft");
    Ok(Some(path))
}

pub fn default_app_config() -> AppConfig {
    let fourteen_days_ago = Utc::now().checked_sub_days(Days::new(14)).unwrap();
    let now = Utc::now();

    AppConfig {
        clip_icons: true,
        last_rss_fetched: fourteen_days_ago.to_rfc3339(),
        curseforge: true,
        modrinth: true,
        curseforge_usage: 0,
        modrinth_usage: 0,
        dev_mode: false,
        hardware_id: Uuid::now_v7().to_string(),
        rss_feeds: true,
        silent_news: false,
        auto_quadrant_sync: true,
        show_unupgradeable_mods: false,
        last_page: 0,
        extended_navigation: false,
        experimental_features: false,
        dont_show_user_data_recommendation: false,
        cache_keep_alive: 30,
        sync_settings: true,
        last_settings_updated: now.to_rfc3339(),
        mc_folder: get_mc_folder()
            .ok()
            .flatten()
            .and_then(|path| path.to_str().map(ToOwned::to_owned))
            .unwrap_or_else(|| ".minecraft".to_string()),
        collect_user_data: cfg!(any(target_os = "macos", target_os = "windows")),
    }
}

pub fn default_update_config() -> UpdateConfig {
    UpdateConfig {
        channel: "stable".to_string(),
    }
}

pub fn ensure_default_app_config(store: &impl SettingsStore) -> Result<()> {
    let defaults = default_app_config();

    ensure_bool(store, "clipIcons", defaults.clip_icons)?;
    ensure_string(store, "lastRSSfetched", defaults.last_rss_fetched)?;
    ensure_bool(store, "curseforge", defaults.curseforge)?;
    ensure_bool(store, "modrinth", defaults.modrinth)?;
    ensure_i64(store, "curseforgeUsage", defaults.curseforge_usage)?;
    ensure_i64(store, "modrinthUsage", defaults.modrinth_usage)?;
    ensure_bool(store, "devMode", defaults.dev_mode)?;
    ensure_string(store, "hardwareId", defaults.hardware_id)?;
    ensure_bool(store, "rssFeeds", defaults.rss_feeds)?;
    ensure_bool(store, "silentNews", defaults.silent_news)?;
    ensure_bool(store, "autoQuadrantSync", defaults.auto_quadrant_sync)?;
    ensure_bool(
        store,
        "showUnupgradeableMods",
        defaults.show_unupgradeable_mods,
    )?;
    ensure_i64(store, "lastPage", defaults.last_page)?;
    ensure_bool(store, "extendedNavigation", defaults.extended_navigation)?;
    ensure_bool(
        store,
        "experimentalFeatures",
        defaults.experimental_features,
    )?;
    ensure_bool(
        store,
        "dontShowUserDataRecommendation",
        defaults.dont_show_user_data_recommendation,
    )?;
    ensure_i64(store, "cacheKeepAlive", defaults.cache_keep_alive)?;
    ensure_bool(store, "syncSettings", defaults.sync_settings)?;
    ensure_string(store, "lastSettingsUpdated", defaults.last_settings_updated)?;
    ensure_string(store, "mcFolder", defaults.mc_folder)?;
    ensure_bool(store, "collectUserData", defaults.collect_user_data)?;
    Ok(())
}

fn ensure_bool(store: &impl SettingsStore, key: &str, default: bool) -> Result<()> {
    if store.get_bool(key)?.is_none() {
        store.set_bool(key, default)?;
    }
    Ok(())
}

fn ensure_i64(store: &impl SettingsStore, key: &str, default: i64) -> Result<()> {
    if store.get_i64(key)?.is_none() {
        store.set_i64(key, default)?;
    }
    Ok(())
}

fn ensure_string(store: &impl SettingsStore, key: &str, default: String) -> Result<()> {
    if store.get_string(key)?.is_none() {
        store.set_string(key, default)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ports::SettingsStore;
    use serde_json::Value;
    use std::{cell::RefCell, collections::HashMap};

    struct MemoryStore {
        values: RefCell<HashMap<String, Value>>,
    }

    impl MemoryStore {
        fn new() -> Self {
            Self {
                values: RefCell::new(HashMap::new()),
            }
        }
    }

    impl SettingsStore for MemoryStore {
        fn get_value(&self, key: &str) -> Result<Option<Value>> {
            Ok(self.values.borrow().get(key).cloned())
        }

        fn set_value(&self, key: &str, value: Value) -> Result<()> {
            self.values.borrow_mut().insert(key.to_string(), value);
            Ok(())
        }

        fn entries(&self) -> Result<Vec<(String, Value)>> {
            Ok(self
                .values
                .borrow()
                .iter()
                .map(|(key, value)| (key.clone(), value.clone()))
                .collect())
        }
    }

    #[test]
    fn app_config_defaults_are_materialized() {
        let store = MemoryStore::new();
        ensure_default_app_config(&store).unwrap();

        assert_eq!(store.get_bool("clipIcons").unwrap(), Some(true));
        assert_eq!(store.get_bool("curseforge").unwrap(), Some(true));
        assert_eq!(store.get_i64("cacheKeepAlive").unwrap(), Some(30));
        assert!(store.get_string("hardwareId").unwrap().is_some());
        assert!(
            store
                .get_string("mcFolder")
                .unwrap()
                .unwrap()
                .ends_with(".minecraft")
        );
    }

    #[test]
    fn mc_folder_resolves_to_minecraft_path() {
        let mc_folder = get_mc_folder().unwrap().unwrap();
        assert!(mc_folder.to_string_lossy().ends_with(".minecraft"));
    }
}
